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

static BASE_PATH: Lazy<RwLock<Option<PathBuf>>> = Lazy::new(|| RwLock::new(None));
static DATABASES: Lazy<RwLock<HashMap<String, Arc<Database>>>> =
    Lazy::new(|| RwLock::new(HashMap::new()));

fn base_path() -> Result<PathBuf, String> {
    BASE_PATH
        .read()
        .clone()
        .ok_or_else(|| "dxtr_box is not initialized".to_string())
}

fn validate_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name == "." || name == ".." || name.contains('/') || name.contains('\\') {
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
        .cloned()
        .ok_or_else(|| format!("box '{name}' is not open"))
}

pub fn init(path: &str) -> Result<(), String> {
    let path = Path::new(path);
    fs::create_dir_all(path).map_err(|e| format!("create base path: {e}"))?;
    *BASE_PATH.write() = Some(path.to_path_buf());
    DATABASES.write().clear();
    Ok(())
}

pub fn open(name: &str) -> Result<(), String> {
    validate_name(name)?;
    if DATABASES.read().contains_key(name) {
        return Ok(());
    }
    let path = file_path(name)?;
    let db = Arc::new(Database::create(&path).map_err(|e| format!("open {path:?}: {e}"))?);
    {
        let write = db.begin_write().map_err(|e| e.to_string())?;
        write.open_table(DATA).map_err(|e| e.to_string())?;
        write.commit().map_err(|e| e.to_string())?;
    }
    DATABASES.write().insert(name.to_string(), db);
    Ok(())
}

pub fn close(name: &str) {
    DATABASES.write().remove(name);
}

pub fn delete_box(name: &str) -> Result<(), String> {
    close(name);
    let path = file_path(name)?;
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
            table.insert(key.as_str(), value.as_slice()).map_err(|e| e.to_string())?;
        }
    }
    write.commit().map_err(|e| e.to_string())
}

pub fn get(name: &str, key: &str) -> Result<Option<Vec<u8>>, String> {
    let db = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    Ok(table.get(key).map_err(|e| e.to_string())?.map(|guard| guard.value().to_vec()))
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
            .map(|item| item.map(|(key, _)| key.value().to_string()).map_err(|e| e.to_string()))
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
        .map(|item| item.map(|(key, _)| key.value().to_string()).map_err(|e| e.to_string()))
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

    fn pack<T: serde::Serialize>(value: &T) -> Vec<u8> {
        rmp_serde::to_vec(value).unwrap()
    }

    #[test]
    fn crud_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("people").unwrap();
        put("people", "alice", &pack(&42_i64)).unwrap();
        assert_eq!(get("people", "alice").unwrap(), Some(pack(&42_i64)));
        assert_eq!(len("people").unwrap(), 1);
        assert_eq!(all_keys("people").unwrap(), vec!["alice".to_string()]);
        delete("people", "alice").unwrap();
        assert_eq!(len("people").unwrap(), 0);
    }

    #[test]
    fn clear_is_atomic_write_transaction() {
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("items").unwrap();
        put_all("items", &[("a".into(), pack(&1_i64)), ("b".into(), pack(&2_i64))]).unwrap();
        clear("items").unwrap();
        assert_eq!(len("items").unwrap(), 0);
    }
}
