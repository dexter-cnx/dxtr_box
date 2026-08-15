from pathlib import Path

path = Path('rust/src/db.rs')
text = path.read_text()


def replace_once(old: str, new: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'expected one match, got {count}: {old[:120]!r}')
    text = text.replace(old, new, 1)


replace_once(
    'use crate::codec::validate_message_pack;\n#[cfg(feature = "encryption")]\nuse crate::crypto;\n',
    'use crate::codec::validate_message_pack;\n#[cfg(feature = "encryption")]\nuse crate::crypto;\n#[cfg(feature = "full")]\nuse crate::index;\n',
)
replace_once(
    'const DATA: TableDefinition<&str, &[u8]> = TableDefinition::new("data");',
    'pub(crate) const DATA: TableDefinition<&str, &[u8]> = TableDefinition::new("data");',
)
replace_once(
    '#[derive(Debug)]\nenum EncryptionState {',
    '#[derive(Debug)]\npub(crate) enum EncryptionState {',
)
replace_once(
    'impl EncryptionState {\n    fn validate_requested_key',
    '''impl EncryptionState {\n    #[cfg(feature = "full")]\n    pub(crate) fn is_encrypted(&self) -> bool {\n        !matches!(self, Self::Plain)\n    }\n\n    fn validate_requested_key''',
)
replace_once(
    'fn database(name: &str) -> Result<(Arc<Database>, Arc<EncryptionState>), String> {',
    'pub(crate) fn database(name: &str) -> Result<(Arc<Database>, Arc<EncryptionState>), String> {',
)
replace_once(
    '''    databases.insert(\n        name.to_string(),\n        OpenDatabase {\n            db,\n            handles: 1,\n            encryption,\n        },\n    );''',
    '''    #[cfg(feature = "full")]\n    index::ensure_tables(&db)?;\n\n    databases.insert(\n        name.to_string(),\n        OpenDatabase {\n            db,\n            handles: 1,\n            encryption,\n        },\n    );''',
)
replace_once(
    '''            let salt = crypto::new_salt();\n            let key = crypto::derive_key(encryption_key, &salt)?;''',
    '''            #[cfg(feature = "full")]\n            {\n                index::ensure_tables(&db)?;\n                if index::has_definitions(&db)? {\n                    return Err(\n                        "cannot encrypt a box with persisted indexes until encrypted index storage is supported"\n                            .to_string(),\n                    );\n                }\n            }\n\n            let salt = crypto::new_salt();\n            let key = crypto::derive_key(encryption_key, &salt)?;''',
)
replace_once(
    '''    let write = db.begin_write().map_err(|e| e.to_string())?;\n    {\n        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;\n        table\n            .insert(key, stored.as_slice())\n            .map_err(|e| e.to_string())?;\n    }\n    write.commit().map_err(|e| e.to_string())\n}\n\npub fn put_all''',
    '''    let write = db.begin_write().map_err(|e| e.to_string())?;\n    {\n        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;\n        let old = table\n            .get(key)\n            .map_err(|e| e.to_string())?\n            .map(|value| value.value().to_vec());\n        #[cfg(feature = "full")]\n        index::maintain_put(&write, key, old.as_deref(), value)?;\n        table\n            .insert(key, stored.as_slice())\n            .map_err(|e| e.to_string())?;\n    }\n    write.commit().map_err(|e| e.to_string())\n}\n\npub fn put_all''',
)
replace_once(
    '''    let (_, encryption) = database(name)?;\n    let mut stored_entries = Vec::with_capacity(entries.len());\n    for (key, value) in entries {\n        validate_message_pack(value)?;\n        stored_entries.push((key.as_str(), encryption.encode_value(key, value)?));\n    }\n\n    let (db, _) = database(name)?;\n    let write = db.begin_write().map_err(|e| e.to_string())?;\n    {\n        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;\n        for (key, value) in &stored_entries {\n            table\n                .insert(*key, value.as_slice())\n                .map_err(|e| e.to_string())?;\n        }\n    }''',
    '''    let (_, encryption) = database(name)?;\n    let mut stored_entries = Vec::with_capacity(entries.len());\n    for (key, value) in entries {\n        validate_message_pack(value)?;\n        stored_entries.push((\n            key.as_str(),\n            value.as_slice(),\n            encryption.encode_value(key, value)?,\n        ));\n    }\n\n    let (db, _) = database(name)?;\n    let write = db.begin_write().map_err(|e| e.to_string())?;\n    {\n        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;\n        for (key, plaintext, stored) in &stored_entries {\n            let old = table\n                .get(*key)\n                .map_err(|e| e.to_string())?\n                .map(|value| value.value().to_vec());\n            #[cfg(feature = "full")]\n            index::maintain_put(&write, key, old.as_deref(), plaintext)?;\n            table\n                .insert(*key, stored.as_slice())\n                .map_err(|e| e.to_string())?;\n        }\n    }''',
)
replace_once(
    '''pub fn delete(name: &str, key: &str) -> Result<(), String> {\n    let (db, _) = database(name)?;\n    let write = db.begin_write().map_err(|e| e.to_string())?;\n    {\n        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;\n        table.remove(key).map_err(|e| e.to_string())?;\n    }\n    write.commit().map_err(|e| e.to_string())\n}''',
    '''pub fn delete(name: &str, key: &str) -> Result<(), String> {\n    let (db, _) = database(name)?;\n    let write = db.begin_write().map_err(|e| e.to_string())?;\n    {\n        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;\n        let old = table\n            .get(key)\n            .map_err(|e| e.to_string())?\n            .map(|value| value.value().to_vec());\n        #[cfg(feature = "full")]\n        if let Some(old) = old.as_deref() {\n            index::maintain_delete(&write, key, old)?;\n        }\n        table.remove(key).map_err(|e| e.to_string())?;\n    }\n    write.commit().map_err(|e| e.to_string())\n}''',
)
replace_once(
    '''        for key in keys {\n            if table\n                .remove(key.as_str())\n                .map_err(|e| e.to_string())?\n                .is_some()\n            {\n                deleted.push(key.clone());\n            }\n        }''',
    '''        for key in keys {\n            let old = table\n                .get(key.as_str())\n                .map_err(|e| e.to_string())?\n                .map(|value| value.value().to_vec());\n            if let Some(old) = old {\n                #[cfg(feature = "full")]\n                index::maintain_delete(&write, key, &old)?;\n                table\n                    .remove(key.as_str())\n                    .map_err(|e| e.to_string())?;\n                deleted.push(key.clone());\n            }\n        }''',
)
replace_once(
    '''        for key in keys {\n            table.remove(key.as_str()).map_err(|e| e.to_string())?;\n        }\n    }\n    write.commit().map_err(|e| e.to_string())\n}\n\n#[cfg(feature = "maintenance")]''',
    '''        for key in keys {\n            table.remove(key.as_str()).map_err(|e| e.to_string())?;\n        }\n        #[cfg(feature = "full")]\n        index::clear_entries(&write)?;\n    }\n    write.commit().map_err(|e| e.to_string())\n}\n\n#[cfg(feature = "maintenance")]''',
)
path.write_text(text)

api_path = Path('rust/src/api.rs')
api = api_path.read_text()


def api_replace_once(old: str, new: str) -> None:
    global api
    count = api.count(old)
    if count != 1:
        raise SystemExit(f'api expected one match, got {count}: {old[:120]!r}')
    api = api.replace(old, new, 1)


api_replace_once(
    '#[cfg(feature = "full")]\nuse crate::query;\nuse crate::{db, frb_generated::StreamSink};',
    '#[cfg(feature = "full")]\nuse crate::{index, query};\nuse crate::{db, frb_generated::StreamSink};',
)
api_replace_once(
    '''pub struct NativeQueryRecord {\n    pub key: String,\n    pub value: Vec<u8>,\n}\n''',
    '''pub struct NativeQueryRecord {\n    pub key: String,\n    pub value: Vec<u8>,\n}\n\npub struct NativeIndexDefinition {\n    pub name: String,\n    pub field: String,\n}\n''',
)
api_replace_once(
    '''pub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {\n    db::all_keys(&box_name)\n}''',
    '''pub fn create_index(box_name: String, name: String, field: String) -> Result<(), String> {\n    #[cfg(feature = "full")]\n    {\n        let mutation_lock = mutation_lock(&box_name);\n        let _mutation_guard = mutation_lock.lock();\n        let (db, encryption) = db::database(&box_name)?;\n        index::create(&db, &encryption, &name, &field)\n    }\n\n    #[cfg(not(feature = "full"))]\n    {\n        let _ = (box_name, name, field);\n        Err("persisted indexes require the full profile".to_string())\n    }\n}\n\npub fn list_indexes(box_name: String) -> Result<Vec<NativeIndexDefinition>, String> {\n    #[cfg(feature = "full")]\n    {\n        let (db, _) = db::database(&box_name)?;\n        return index::list(&db).map(|definitions| {\n            definitions\n                .into_iter()\n                .map(|(name, field)| NativeIndexDefinition { name, field })\n                .collect()\n        });\n    }\n\n    #[cfg(not(feature = "full"))]\n    {\n        let _ = box_name;\n        Err("persisted indexes require the full profile".to_string())\n    }\n}\n\npub fn drop_index(box_name: String, name: String) -> Result<bool, String> {\n    #[cfg(feature = "full")]\n    {\n        let mutation_lock = mutation_lock(&box_name);\n        let _mutation_guard = mutation_lock.lock();\n        let (db, _) = db::database(&box_name)?;\n        index::drop_index(&db, &name)\n    }\n\n    #[cfg(not(feature = "full"))]\n    {\n        let _ = (box_name, name);\n        Err("persisted indexes require the full profile".to_string())\n    }\n}\n\npub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {\n    db::all_keys(&box_name)\n}''',
)
api_path.write_text(api)
