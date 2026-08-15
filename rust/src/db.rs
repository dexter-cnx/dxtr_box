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
#[cfg(feature = "encryption")]
use crate::crypto;

const DATA: TableDefinition<&str, &[u8]> = TableDefinition::new("data");
const META: TableDefinition<&str, &[u8]> = TableDefinition::new("meta");
const META_FORMAT_VERSION: &str = "format_version";
const META_ENCRYPTION_MODE: &str = "encryption_mode";
#[cfg(feature = "encryption")]
const META_ENCRYPTION_SALT: &str = "encryption_salt";
#[cfg(feature = "encryption")]
const META_KEY_CHECK: &str = "key_check";
const FORMAT_VERSION: &[u8] = b"dxtr_box/1";
const ENCRYPTION_NONE: &[u8] = b"none";
const ENCRYPTION_CHACHA20POLY1305: &[u8] = b"chacha20poly1305";
#[cfg(feature = "encryption")]
const KEY_CHECK_PLAINTEXT: &[u8] = b"dxtr_box:key-check:v1";

#[derive(Debug)]
enum EncryptionState {
    Plain,
    #[cfg(feature = "encryption")]
    Encrypted {
        key: [u8; 32],
        salt: [u8; crypto::SALT_LEN],
    },
}

impl EncryptionState {
    fn validate_requested_key(&self, encryption_key: Option<&str>) -> Result<(), String> {
        match self {
            Self::Plain => {
                if encryption_key.is_some() {
                    Err("box is not encrypted; omit encryptionKey".to_string())
                } else {
                    Ok(())
                }
            }
            #[cfg(feature = "encryption")]
            Self::Encrypted { key, salt } => {
                let password = encryption_key
                    .ok_or_else(|| "encryption key is required for encrypted box".to_string())?;
                if password.is_empty() {
                    return Err("encryption key cannot be empty".to_string());
                }
                let candidate = crypto::derive_key(password, salt)?;
                if &candidate == key {
                    Ok(())
                } else {
                    Err("invalid encryption key".to_string())
                }
            }
        }
    }

    fn encode_value(&self, record_key: &str, plaintext: &[u8]) -> Result<Vec<u8>, String> {
        match self {
            Self::Plain => Ok(plaintext.to_vec()),
            #[cfg(feature = "encryption")]
            Self::Encrypted { key, .. } => {
                crypto::encrypt_with_aad(key, record_key.as_bytes(), plaintext)
            }
        }
    }

    fn decode_value(&self, record_key: &str, stored: &[u8]) -> Result<Vec<u8>, String> {
        match self {
            Self::Plain => Ok(stored.to_vec()),
            #[cfg(feature = "encryption")]
            Self::Encrypted { key, .. } => {
                crypto::decrypt_with_aad(key, record_key.as_bytes(), stored)
                    .map_err(|_| "encrypted value authentication failed".to_string())
            }
        }
    }
}

struct OpenDatabase {
    db: Arc<Database>,
    handles: usize,
    encryption: Arc<EncryptionState>,
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

fn database(name: &str) -> Result<(Arc<Database>, Arc<EncryptionState>), String> {
    DATABASES
        .read()
        .get(name)
        .map(|entry| (Arc::clone(&entry.db), Arc::clone(&entry.encryption)))
        .ok_or_else(|| format!("box '{name}' is not open"))
}

fn read_meta(db: &Database, key: &str) -> Result<Option<Vec<u8>>, String> {
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(META).map_err(|e| e.to_string())?;
    Ok(table
        .get(key)
        .map_err(|e| e.to_string())?
        .map(|value| value.value().to_vec()))
}

fn write_plain_metadata(db: &Database) -> Result<(), String> {
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut meta = write.open_table(META).map_err(|e| e.to_string())?;
        meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
            .map_err(|e| e.to_string())?;
        meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_NONE)
            .map_err(|e| e.to_string())?;
    }
    write.commit().map_err(|e| e.to_string())
}

fn initialize_new_box(
    db: &Database,
    encryption_key: Option<&str>,
) -> Result<EncryptionState, String> {
    match encryption_key {
        None => {
            let write = db.begin_write().map_err(|e| e.to_string())?;
            {
                write.open_table(DATA).map_err(|e| e.to_string())?;
                let mut meta = write.open_table(META).map_err(|e| e.to_string())?;
                meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                    .map_err(|e| e.to_string())?;
                meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_NONE)
                    .map_err(|e| e.to_string())?;
            }
            write.commit().map_err(|e| e.to_string())?;
            Ok(EncryptionState::Plain)
        }
        Some(password) => {
            if password.is_empty() {
                return Err("encryption key cannot be empty".to_string());
            }
            #[cfg(feature = "encryption")]
            {
                let salt = crypto::new_salt();
                let key = crypto::derive_key(password, &salt)?;
                let key_check = crypto::encrypt(&key, KEY_CHECK_PLAINTEXT)?;
                let write = db.begin_write().map_err(|e| e.to_string())?;
                {
                    write.open_table(DATA).map_err(|e| e.to_string())?;
                    let mut meta = write.open_table(META).map_err(|e| e.to_string())?;
                    meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                        .map_err(|e| e.to_string())?;
                    meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_CHACHA20POLY1305)
                        .map_err(|e| e.to_string())?;
                    meta.insert(META_ENCRYPTION_SALT, salt.as_slice())
                        .map_err(|e| e.to_string())?;
                    meta.insert(META_KEY_CHECK, key_check.as_slice())
                        .map_err(|e| e.to_string())?;
                }
                write.commit().map_err(|e| e.to_string())?;
                Ok(EncryptionState::Encrypted { key, salt })
            }
            #[cfg(not(feature = "encryption"))]
            {
                let _ = password;
                Err("this native build was compiled without encryption support".to_string())
            }
        }
    }
}

fn resolve_existing_box(
    db: &Database,
    encryption_key: Option<&str>,
) -> Result<EncryptionState, String> {
    let format = read_meta(db, META_FORMAT_VERSION)?;

    // Files created before metadata support are known plaintext boxes. Persist
    // the v1 marker on first reopen, but never reinterpret existing plaintext
    // data as encrypted just because a caller supplied a key.
    if format.is_none() {
        if encryption_key.is_some() {
            return Err(
                "cannot enable encryption on an existing plaintext box; migrate explicitly"
                    .to_string(),
            );
        }
        write_plain_metadata(db)?;
        return Ok(EncryptionState::Plain);
    }

    if format.as_deref() != Some(FORMAT_VERSION) {
        return Err("unsupported dxtr_box storage format".to_string());
    }

    let mode = read_meta(db, META_ENCRYPTION_MODE)?
        .ok_or_else(|| "box metadata is missing encryption mode".to_string())?;

    if mode == ENCRYPTION_NONE {
        if encryption_key.is_some() {
            return Err("box is not encrypted; omit encryptionKey".to_string());
        }
        return Ok(EncryptionState::Plain);
    }

    if mode == ENCRYPTION_CHACHA20POLY1305 {
        #[cfg(feature = "encryption")]
        {
            let password = encryption_key
                .ok_or_else(|| "encryption key is required for encrypted box".to_string())?;
            if password.is_empty() {
                return Err("encryption key cannot be empty".to_string());
            }

            let salt_bytes = read_meta(db, META_ENCRYPTION_SALT)?
                .ok_or_else(|| "encrypted box metadata is missing salt".to_string())?;
            let salt: [u8; crypto::SALT_LEN] = salt_bytes
                .try_into()
                .map_err(|_| "encrypted box metadata has invalid salt length".to_string())?;
            let key_check = read_meta(db, META_KEY_CHECK)?
                .ok_or_else(|| "encrypted box metadata is missing key check".to_string())?;
            let key = crypto::derive_key(password, &salt)?;
            let plaintext = crypto::decrypt(&key, &key_check)
                .map_err(|_| "invalid encryption key".to_string())?;
            if plaintext != KEY_CHECK_PLAINTEXT {
                return Err("invalid encryption key".to_string());
            }
            return Ok(EncryptionState::Encrypted { key, salt });
        }
        #[cfg(not(feature = "encryption"))]
        {
            let _ = encryption_key;
            return Err("this native build was compiled without encryption support".to_string());
        }
    }

    Err("unsupported box encryption mode".to_string())
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

pub fn open(name: &str, encryption_key: Option<&str>) -> Result<(), String> {
    validate_name(name)?;
    if matches!(encryption_key, Some("")) {
        return Err("encryption key cannot be empty".to_string());
    }

    let path = file_path(name)?;
    let existed = path.exists();
    let mut databases = DATABASES.write();

    if let Some(entry) = databases.get_mut(name) {
        entry.encryption.validate_requested_key(encryption_key)?;
        entry.handles += 1;
        return Ok(());
    }

    let db = Arc::new(Database::create(&path).map_err(|e| format!("open {path:?}: {e}"))?);
    let had_data_table = if existed {
        let read = db.begin_read().map_err(|e| e.to_string())?;
        read.open_table(DATA).is_ok()
    } else {
        false
    };

    let encryption = if existed && had_data_table {
        {
            let write = db.begin_write().map_err(|e| e.to_string())?;
            write.open_table(DATA).map_err(|e| e.to_string())?;
            write.open_table(META).map_err(|e| e.to_string())?;
            write.commit().map_err(|e| e.to_string())?;
        }
        resolve_existing_box(&db, encryption_key)
    } else {
        // A file without the data table is an interrupted first creation,
        // not a legacy plaintext box. Re-run the atomic initializer.
        initialize_new_box(&db, encryption_key)
    };

    let encryption = match encryption {
        Ok(state) => Arc::new(state),
        Err(error) => {
            drop(db);
            if !existed || !had_data_table {
                let _ = fs::remove_file(&path);
            }
            return Err(error);
        }
    };

    databases.insert(
        name.to_string(),
        OpenDatabase {
            db,
            handles: 1,
            encryption,
        },
    );
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
    let (db, encryption) = database(name)?;
    let stored = encryption.encode_value(key, value)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        table
            .insert(key, stored.as_slice())
            .map_err(|e| e.to_string())?;
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn put_all(name: &str, entries: &[(String, Vec<u8>)]) -> Result<(), String> {
    let (_, encryption) = database(name)?;
    let mut stored_entries = Vec::with_capacity(entries.len());
    for (key, value) in entries {
        validate_message_pack(value)?;
        stored_entries.push((key.as_str(), encryption.encode_value(key, value)?));
    }

    let (db, _) = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        for (key, value) in &stored_entries {
            table
                .insert(*key, value.as_slice())
                .map_err(|e| e.to_string())?;
        }
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn get(name: &str, key: &str) -> Result<Option<Vec<u8>>, String> {
    let (db, encryption) = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    let stored = table
        .get(key)
        .map_err(|e| e.to_string())?
        .map(|guard| guard.value().to_vec());
    drop(table);
    drop(read);

    match stored {
        None => Ok(None),
        Some(payload) => {
            let plaintext = encryption.decode_value(key, &payload)?;
            validate_message_pack(&plaintext)?;
            Ok(Some(plaintext))
        }
    }
}

pub fn contains_key(name: &str, key: &str) -> Result<bool, String> {
    let (db, _) = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    Ok(table.get(key).map_err(|e| e.to_string())?.is_some())
}

pub fn delete(name: &str, key: &str) -> Result<(), String> {
    let (db, _) = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        table.remove(key).map_err(|e| e.to_string())?;
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn delete_all(name: &str, keys: &[String]) -> Result<Vec<String>, String> {
    let (db, _) = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    let mut deleted = Vec::new();
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        for key in keys {
            if table
                .remove(key.as_str())
                .map_err(|e| e.to_string())?
                .is_some()
            {
                deleted.push(key.clone());
            }
        }
    }
    write.commit().map_err(|e| e.to_string())?;
    Ok(deleted)
}

pub fn clear(name: &str) -> Result<(), String> {
    let (db, _) = database(name)?;
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

pub fn compact(name: &str) -> Result<bool, String> {
    let mut databases = DATABASES.write();
    let entry = databases
        .get_mut(name)
        .ok_or_else(|| format!("box '{name}' is not open"))?;
    if entry.handles != 1 {
        return Err("compact requires exactly one open box handle".to_string());
    }
    let db = Arc::get_mut(&mut entry.db)
        .ok_or_else(|| "box is busy; retry compact when no operations are in flight".to_string())?;

    let mut compacted = false;
    while db.compact().map_err(|e| e.to_string())? {
        compacted = true;
    }
    Ok(compacted)
}

pub fn all_keys(name: &str) -> Result<Vec<String>, String> {
    let (db, _) = database(name)?;
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
    let (db, _) = database(name)?;
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
        open("people", None).unwrap();
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
    fn delete_all_is_atomic_and_reports_existing_keys() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("batch-delete", None).unwrap();
        put_all(
            "batch-delete",
            &[
                ("a".into(), pack(&1_i64)),
                ("b".into(), pack(&2_i64)),
                ("c".into(), pack(&3_i64)),
            ],
        )
        .unwrap();

        let deleted = delete_all(
            "batch-delete",
            &["a".to_string(), "missing".to_string(), "c".to_string()],
        )
        .unwrap();
        assert_eq!(deleted, vec!["a".to_string(), "c".to_string()]);
        assert_eq!(all_keys("batch-delete").unwrap(), vec!["b".to_string()]);
        close("batch-delete");
    }

    #[test]
    fn compact_requires_a_single_idle_handle() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("compact", None).unwrap();
        put_all(
            "compact",
            &(0..128)
                .map(|index| (format!("key-{index}"), pack(&vec![index as u8; 1024])))
                .collect::<Vec<_>>(),
        )
        .unwrap();
        clear("compact").unwrap();

        assert!(compact("compact").is_ok());
        open("compact", None).unwrap();
        assert!(compact("compact").is_err());
        close("compact");
        close("compact");
    }

    #[test]
    fn clear_is_atomic_write_transaction() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("items", None).unwrap();
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
        open("persistent", None).unwrap();
        put("persistent", "answer", &pack(&42_i64)).unwrap();
        close("persistent");

        open("persistent", None).unwrap();
        assert_eq!(get("persistent", "answer").unwrap(), Some(pack(&42_i64)));
        assert_eq!(len("persistent").unwrap(), 1);
        close("persistent");
    }

    #[test]
    fn put_all_rejects_invalid_payload_before_writing() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("atomic", None).unwrap();

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
            assert!(
                open(name, None).is_err(),
                "name should be rejected: {name:?}"
            );
        }
    }

    #[test]
    fn repeated_init_is_idempotent_and_path_change_requires_no_open_boxes() {
        let _guard = TEST_LOCK.lock();
        let first = tempfile::tempdir().unwrap();
        let second = tempfile::tempdir().unwrap();
        init(first.path().to_str().unwrap()).unwrap();
        init(first.path().to_str().unwrap()).unwrap();

        open("active", None).unwrap();
        assert!(init(second.path().to_str().unwrap()).is_err());
        close("active");

        init(second.path().to_str().unwrap()).unwrap();
    }

    #[test]
    fn closing_one_handle_keeps_other_handle_alive() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("shared", None).unwrap();
        open("shared", None).unwrap();
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
        open("temporary", None).unwrap();
        put("temporary", "k", &pack(&1_i64)).unwrap();
        assert!(box_exists("temporary").unwrap());

        assert!(delete_box("temporary").is_err());
        assert!(box_exists("temporary").unwrap());
        close("temporary");

        delete_box("temporary").unwrap();
        assert!(!box_exists("temporary").unwrap());
        assert!(get("temporary", "k").is_err());
    }

    #[cfg(feature = "encryption")]
    #[test]
    fn encrypted_values_round_trip_and_remain_encrypted_on_disk() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("secure", Some("correct horse battery staple")).unwrap();
        let plaintext = pack(&"secret-value");
        put("secure", "token", &plaintext).unwrap();
        assert_eq!(get("secure", "token").unwrap(), Some(plaintext.clone()));

        let (db, _) = database("secure").unwrap();
        let read = db.begin_read().unwrap();
        let table = read.open_table(DATA).unwrap();
        let stored = table.get("token").unwrap().unwrap().value().to_vec();
        assert_ne!(stored, plaintext);
        close("secure");
    }

    #[cfg(feature = "encryption")]
    #[test]
    fn encrypted_box_requires_the_same_key_after_reopen() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("secure-reopen", Some("first-key")).unwrap();
        put("secure-reopen", "answer", &pack(&42_i64)).unwrap();
        close("secure-reopen");

        assert!(open("secure-reopen", None).is_err());
        assert!(open("secure-reopen", Some("wrong-key")).is_err());
        open("secure-reopen", Some("first-key")).unwrap();
        assert_eq!(get("secure-reopen", "answer").unwrap(), Some(pack(&42_i64)));
        close("secure-reopen");
    }

    #[cfg(feature = "encryption")]
    #[test]
    fn encrypted_boxes_use_unique_persisted_salts() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();

        open("secure-a", Some("password")).unwrap();
        let (db_a, _) = database("secure-a").unwrap();
        let salt_a = read_meta(&db_a, META_ENCRYPTION_SALT).unwrap().unwrap();
        drop(db_a);
        close("secure-a");

        open("secure-b", Some("password")).unwrap();
        let (db_b, _) = database("secure-b").unwrap();
        let salt_b = read_meta(&db_b, META_ENCRYPTION_SALT).unwrap().unwrap();
        drop(db_b);
        close("secure-b");

        assert_eq!(salt_a.len(), crypto::SALT_LEN);
        assert_eq!(salt_b.len(), crypto::SALT_LEN);
        assert_ne!(salt_a, salt_b);

        open("secure-a", Some("password")).unwrap();
        let (db_a_reopened, _) = database("secure-a").unwrap();
        assert_eq!(
            read_meta(&db_a_reopened, META_ENCRYPTION_SALT)
                .unwrap()
                .unwrap(),
            salt_a
        );
        drop(db_a_reopened);
        close("secure-a");
    }

    #[cfg(feature = "encryption")]
    #[test]
    fn swapping_encrypted_payloads_between_keys_is_rejected() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("swap", Some("password")).unwrap();
        put("swap", "a", &pack(&"first")).unwrap();
        put("swap", "b", &pack(&"second")).unwrap();

        let (db, _) = database("swap").unwrap();
        let (payload_a, payload_b) = {
            let read = db.begin_read().unwrap();
            let table = read.open_table(DATA).unwrap();
            (
                table.get("a").unwrap().unwrap().value().to_vec(),
                table.get("b").unwrap().unwrap().value().to_vec(),
            )
        };
        let write = db.begin_write().unwrap();
        {
            let mut table = write.open_table(DATA).unwrap();
            table.insert("a", payload_b.as_slice()).unwrap();
            table.insert("b", payload_a.as_slice()).unwrap();
        }
        write.commit().unwrap();

        assert!(get("swap", "a").is_err());
        assert!(get("swap", "b").is_err());
        drop(db);
        close("swap");
    }

    #[cfg(feature = "encryption")]
    #[test]
    fn tampered_encrypted_value_is_rejected() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("tamper", Some("password")).unwrap();
        put("tamper", "key", &pack(&"value")).unwrap();

        let (db, _) = database("tamper").unwrap();
        let write = db.begin_write().unwrap();
        {
            let mut table = write.open_table(DATA).unwrap();
            let mut stored = table.get("key").unwrap().unwrap().value().to_vec();
            let last = stored.len() - 1;
            stored[last] ^= 0x01;
            table.insert("key", stored.as_slice()).unwrap();
        }
        write.commit().unwrap();

        assert!(get("tamper", "key").is_err());
        close("tamper");
    }

    #[cfg(feature = "encryption")]
    #[test]
    fn plaintext_box_cannot_be_reopened_as_encrypted() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("plain", None).unwrap();
        put("plain", "key", &pack(&1_i64)).unwrap();
        close("plain");

        assert!(open("plain", Some("password")).is_err());
        open("plain", None).unwrap();
        assert_eq!(get("plain", "key").unwrap(), Some(pack(&1_i64)));
        close("plain");
    }
}
