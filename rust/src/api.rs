use flutter_rust_bridge::frb;

use crate::db;

#[frb(sync)]
pub fn init_db(path: String) -> Result<(), String> {
    db::init(&path)
}

#[frb(sync)]
pub fn open_box(name: String, encryption_key: Option<String>) -> Result<(), String> {
    if encryption_key.is_some() {
        return Err(
            "encryption is reserved for milestone 0.2.0; enable feature wiring first".into(),
        );
    }
    db::open(&name)
}

#[frb(sync)]
pub fn close_box(name: String) -> Result<(), String> {
    db::close(&name);
    Ok(())
}

#[frb(sync)]
pub fn delete_box(name: String) -> Result<(), String> {
    db::delete_box(&name)
}

#[frb(sync)]
pub fn box_exists(name: String) -> Result<bool, String> {
    db::box_exists(&name)
}

pub fn put(box_name: String, key: String, value: Vec<u8>) -> Result<(), String> {
    db::put(&box_name, &key, &value)
}

pub fn put_all(box_name: String, entries: Vec<(String, Vec<u8>)>) -> Result<(), String> {
    db::put_all(&box_name, &entries)
}

pub fn get(box_name: String, key: String) -> Result<Option<Vec<u8>>, String> {
    db::get(&box_name, &key)
}

pub fn contains_key(box_name: String, key: String) -> Result<bool, String> {
    db::contains_key(&box_name, &key)
}

pub fn delete(box_name: String, key: String) -> Result<(), String> {
    db::delete(&box_name, &key)
}

pub fn clear(box_name: String) -> Result<(), String> {
    db::clear(&box_name)
}

pub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {
    db::all_keys(&box_name)
}

pub fn length(box_name: String) -> Result<u64, String> {
    db::len(&box_name)
}
