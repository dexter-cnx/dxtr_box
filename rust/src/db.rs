use once_cell::sync::Lazy;
use parking_lot::RwLock;
use redb::{Database, ReadableTable, ReadableTableMetadata, TableDefinition};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    sync::Arc,
};

use crate::codec::validate_message_pack;

const DATA: TableDefinition<&str, &[u8]> = TableDefinition::new("data");

struct OpenDatabase {
    db: Arc<Database>,
    handles: usize,
}

static BASE_PATH: Lazy<RwLock<Option<PathBuf>>> = Lazy::new(|| RwLock::new(None));
static DATABASES: Lazy<RwLock<HashMap<String, OpenDatabase>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

fn base_path() -> Result<PathBuf, String> {
    BASE_PATH
        .read()
        .clone()
        .ok_or_else(|| "dxtr_box is not initialized".to_string())
}

fn validate_name(name: &str) -> Result<(), String> {
    let windows_stem = name
        .split('.')
        .next()
        .unwrap_or_default()
        .to_ascii_uppercase();
    let reserved_windows_name = matches!(
        windows_stem.as_str(),
        "CON"
            | "PRN"
            | "AUX"
            | "NUL"
            | "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
    );
    let unsafe_character = name
        .chars()
        .any(|character| character.is_control() || "<>:\"/\\|?*".contains(character));

    if name.is_empty()
        || name == "."
        || name == ".."
        || name.ends_with('.')
        || name.ends_with(' ')
        || unsafe_character
        || reserved_windows_name
    {
        return Err("invalid box name".to_string());
    }
    Ok(())
}

fn file_path(name: &str) -> Result<PathBuf, String> {
    validate_name(name)?;
    Ok(base_path()?.join(format!("{name}.dxtr")))
}

fn database(name: &str) -> Result<Arc<Database>, String> {
    DATABASES
        .read()
        .get(name)
        .map(|entry| Arc::clone(&entry.db))
        .ok_or_else(|| format!("box '{name}' is not open"))
}

pub fn init(path: &str) -> Result<(), String> {
    let requested_path = Path::new(path);
    fs::create_dir_all(requested_path).map_err(|e| format!("create base path: {e}"))?;
    let resolved_path = fs::canonicalize(requested_path)
        .map_err(|e| format!("resolve base path {requested_path:?}: {e}"))?;

    if let Some(current_path) = BASE_PATH.read().clone() {
        if current_path == resolved_path {
            return Ok(());
        }
        if !DATABASES.read().is_empty() {
            return Err("cannot change base path while boxes are open".to_string());
        }
    }

    *BASE_PATH.write() = Some(resolved_path);
    Ok(())
}

pub fn open(name: &str) -> Result<(), String> {
    validate_name(name)?;
    let path = file_path(name)?;
    let mut databases = DATABASES.write();

    if let Some(entry) = databases.get_mut(name) {
        entry.handles += 1;
        return Ok(());
    }

    let db = Arc::new(Database::create(&path).map_err(|e| format!("open {path:?}: {e}"))?);
    {
        let write = db.begin_write().map_err(|e| e.to_string())?;
        write.open_table(DATA).map_err(|e| e.to_string())?;
        write.commit().map_err(|e| e.to_string())?;
    }
    databases.insert(name.to_string(), OpenDatabase { db, handles: 1 });
    Ok(())
}

pub fn close(name: &str) {
    let mut databases = DATABASES.write();
    let should_remove = match databases.get_mut(name) {
        Some(entry) if entry.handles > 1 => {
            entry.handles -= 1;
            false
        }
        Some(_) => true,
        None => false,
    };
    if should_remove {
        databases.remove(name);
    }
}

pub fn delete_box(name: &str) -> Result<(), String> {
    validate_name(name)?;
    let path = file_path(name)?;
    let databases = DATABASES.write();
    if databases.contains_key(name) {
        return Err(format!("cannot delete open box '{name}'"));
    }

    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(format!("delete box: {e}")),
    }
}

pub fn box_exists(name: &str) -> Result<bool, String> {
    Ok(file_path(name)?.exists())
}

pub fn put(name: &str, key: &str, value: &[u8]) -> Result<(), String> {
    validate_message_pack(value)?;
    let db = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        table.insert(key, value).map_err(|e| e.to_string())?;
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn put_all(name: &str, entries: &[(String, Vec<u8>)]) -> Result<(), String> {
    for (_, value) in entries {
        validate_message_pack(value)?;
    }
    let db = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        for (key, value) in entries {
            table
                .insert(key.as_str(), value.as_slice())
                .map_err(|e| e.to_string())?;
        }
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn get(name: &str, key: &str) -> Result<Option<Vec<u8>>, String> {
    let db = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    Ok(table
        .get(key)
        .map_err(|e| e.to_string())?
        .map(|guard| guard.value().to_vec()))
}

pub fn contains_key(name: &str, key: &str) -> Result<bool, String> {
    Ok(get(name, key)?.is_some())
}

pub fn delete(name: &str, key: &str) -> Result<(), String> {
    let db = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        table.remove(key).map_err(|e| e.to_string())?;
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn clear(name: &str) -> Result<(), String> {
    let db = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        let keys: Vec<String> = table
            .iter()
            .map_err(|e| e.to_string())?
            .map(|item| {
                item.map(|(key, _)| key.value().to_string())
                    .map_err(|e| e.to_string())
            })
            .collect::<Result<_, _>>()?;
        for key in keys {
            table.remove(key.as_str()).map_err(|e| e.to_string())?;
        }
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn all_keys(name: &str) -> Result<Vec<String>, String> {
    let db = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    table
        .iter()
        .map_err(|e| e.to_string())?
        .map(|item| {
            item.map(|(key, _)| key.value().to_string())
                .map_err(|e| e.to_string())
        })
        .collect()
}

pub fn len(name: &str) -> Result<u64, String> {
    let db = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    table.len().map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use once_cell::sync::Lazy;
    use parking_lot::Mutex;

    // The engine intentionally keeps process-global base-path and database caches.
    // Serialize tests that mutate that global state so `cargo test` remains deterministic.
    static TEST_LOCK: Lazy<Mutex<()>> = Lazy::new(|| Mutex::new(()));

    fn pack<T: serde::Serialize>(value: &T) -> Vec<u8> {
        rmp_serde::to_vec(value).unwrap()
    }

    #[test]
    fn crud_round_trip() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("people").unwrap();
        put("people", "alice", &pack(&42_i64)).unwrap();
        assert_eq!(get("people", "alice").unwrap(), Some(pack(&42_i64)));
        assert!(contains_key("people", "alice").unwrap());
        assert_eq!(len("people").unwrap(), 1);
        assert_eq!(all_keys("people").unwrap(), vec!["alice".to_string()]);
        delete("people", "alice").unwrap();
        assert!(!contains_key("people", "alice").unwrap());
        assert_eq!(len("people").unwrap(), 0);
        close("people");
    }

    #[test]
    fn clear_is_atomic_write_transaction() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("items").unwrap();
        put_all(
            "items",
            &[("a".into(), pack(&1_i64)), ("b".into(), pack(&2_i64))],
        )
        .unwrap();
        clear("items").unwrap();
        assert_eq!(len("items").unwrap(), 0);
        close("items");
    }

    #[test]
    fn data_survives_close_and_reopen() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("persistent").unwrap();
        put("persistent", "answer", &pack(&42_i64)).unwrap();
        close("persistent");

        open("persistent").unwrap();
        assert_eq!(get("persistent", "answer").unwrap(), Some(pack(&42_i64)));
        assert_eq!(len("persistent").unwrap(), 1);
        close("persistent");
    }

    #[test]
    fn put_all_rejects_invalid_payload_before_writing() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("atomic").unwrap();

        let entries = vec![
            ("good".to_string(), pack(&1_i64)),
            ("bad".to_string(), vec![0xc1]), // Reserved MessagePack byte.
        ];
        assert!(put_all("atomic", &entries).is_err());
        assert_eq!(len("atomic").unwrap(), 0);
        close("atomic");
    }

    #[test]
    fn invalid_box_names_are_rejected() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();

        for name in [
            "",
            ".",
            "..",
            "nested/box",
            "nested\\box",
            "bad:name",
            "trailing.",
            "trailing ",
            "CON",
            "con.txt",
            "LPT9",
        ] {
            assert!(open(name).is_err(), "name should be rejected: {name:?}");
        }
    }

    #[test]
    fn repeated_init_is_idempotent_and_path_change_requires_no_open_boxes() {
        let _guard = TEST_LOCK.lock();
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        init(first.path().to_str().unwrap()).unwrap();
        init(first.path().to_str().unwrap()).unwrap();

        open("active").unwrap();
        assert!(init(second.path().to_str().unwrap()).is_err());
        close("active");

        init(second.path().to_str().unwrap()).unwrap();
    }

    #[test]
    fn closing_one_handle_keeps_other_handle_alive() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("shared").unwrap();
        open("shared").unwrap();
        put("shared", "k", &pack(&1_i64)).unwrap();

        close("shared");
        assert_eq!(get("shared", "k").unwrap(), Some(pack(&1_i64)));

        close("shared");
        assert!(get("shared", "k").is_err());
    }

    #[test]
    fn delete_box_rejects_open_handles() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("temporary").unwrap();
        put("temporary", "k", &pack(&1_i64)).unwrap();
        assert!(box_exists("temporary").unwrap());

        assert!(delete_box("temporary").is_err());
        assert!(box_exists("temporary").unwrap());
        close("temporary");

        delete_box("temporary").unwrap();
        assert!(!box_exists("temporary").unwrap());
        assert!(get("temporary", "k").is_err());
    }
}
