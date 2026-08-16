from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"missing expected text in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


# db.rs: expose full-profile query helpers that reuse an existing read snapshot.
replace_once(
    "rust/src/db.rs",
    "use redb::{Database, ReadableTable, ReadableTableMetadata, TableDefinition};\n",
    "use redb::{Database, ReadableTable, ReadableTableMetadata, TableDefinition};\n#[cfg(feature = \"full\")]\nuse redb::ReadTransaction;\n",
)

needle = '''pub fn contains_key(name: &str, key: &str) -> Result<bool, String> {\n'''
helpers = '''#[cfg(feature = "full")]\npub(crate) fn query_all_keys(read: &ReadTransaction) -> Result<Vec<String>, String> {\n    let table = read.open_table(DATA).map_err(|e| e.to_string())?;\n    table\n        .iter()\n        .map_err(|e| e.to_string())?\n        .map(|item| {\n            item.map(|(key, _)| key.value().to_string())\n                .map_err(|e| e.to_string())\n        })\n        .collect()\n}\n\n#[cfg(feature = "full")]\npub(crate) fn query_get(\n    read: &ReadTransaction,\n    encryption: &EncryptionState,\n    key: &str,\n) -> Result<Option<Vec<u8>>, String> {\n    let table = read.open_table(DATA).map_err(|e| e.to_string())?;\n    let stored = table\n        .get(key)\n        .map_err(|e| e.to_string())?\n        .map(|guard| guard.value().to_vec());\n    drop(table);\n\n    match stored {\n        None => Ok(None),\n        Some(payload) => {\n            let plaintext = encryption.decode_value(key, &payload)?;\n            validate_message_pack(&plaintext)?;\n            Ok(Some(plaintext))\n        }\n    }\n}\n\npub fn contains_key(name: &str, key: &str) -> Result<bool, String> {\n'''
replace_once("rust/src/db.rs", needle, helpers)

# Add a snapshot regression test inside db.rs.
needle = '''    #[test]\n    fn delete_all_is_atomic_and_reports_existing_keys() {\n'''
test = '''    #[cfg(feature = "full")]\n    #[test]\n    fn query_helpers_read_one_stable_snapshot() {\n        let _guard = TEST_LOCK.lock();\n        let dir = tempfile::tempdir().unwrap();\n        init(dir.path().to_str().unwrap()).unwrap();\n        open("query-snapshot", None).unwrap();\n        put("query-snapshot", "before", &pack(&1_i64)).unwrap();\n\n        let (database, encryption) = database("query-snapshot").unwrap();\n        let read = database.begin_read().unwrap();\n        assert_eq!(query_all_keys(&read).unwrap(), vec!["before".to_string()]);\n\n        put("query-snapshot", "after", &pack(&2_i64)).unwrap();\n\n        assert_eq!(query_all_keys(&read).unwrap(), vec!["before".to_string()]);\n        assert_eq!(\n            query_get(&read, &encryption, "before").unwrap(),\n            Some(pack(&1_i64))\n        );\n        assert_eq!(query_get(&read, &encryption, "after").unwrap(), None);\n\n        drop(read);\n        assert_eq!(\n            all_keys("query-snapshot").unwrap(),\n            vec!["after".to_string(), "before".to_string()]\n        );\n        close("query-snapshot");\n    }\n\n    #[test]\n    fn delete_all_is_atomic_and_reports_existing_keys() {\n'''
replace_once("rust/src/db.rs", needle, test)

# index.rs: let candidate planning reuse the caller's read transaction.
replace_once(
    "rust/src/index.rs",
    "use redb::{Database, ReadableTable, TableDefinition, WriteTransaction};\n",
    "use redb::{Database, ReadTransaction, ReadableTable, TableDefinition, WriteTransaction};\n",
)

needle = '''pub(crate) fn candidate_keys(\n    db: &Database,\n    filter: &query::Filter,\n) -> Result<Option<Vec<String>>, String> {\n'''
replacement = '''pub(crate) fn candidate_keys(\n    read: &ReadTransaction,\n    filter: &query::Filter,\n) -> Result<Option<Vec<String>>, String> {\n'''
replace_once("rust/src/index.rs", needle, replacement)
replace_once("rust/src/index.rs", "    let definitions = list(db)?;\n", "    let definitions = list_in_read(read)?;\n")
replace_once(
    "rust/src/index.rs",
    "            lookup_candidate(db, index_name, &candidate)?\n",
    "            lookup_candidate(read, index_name, &candidate)?\n",
)

needle = '''fn lookup_candidate(\n    db: &Database,\n    index_name: &str,\n    candidate: &query::IndexCandidate,\n) -> Result<Vec<String>, String> {\n'''
replacement = '''fn lookup_candidate(\n    read: &ReadTransaction,\n    index_name: &str,\n    candidate: &query::IndexCandidate,\n) -> Result<Vec<String>, String> {\n'''
replace_once("rust/src/index.rs", needle, replacement)
replace_once(
    "rust/src/index.rs",
    "    let read = db.begin_read().map_err(|e| e.to_string())?;\n    let entries = read.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;\n",
    "    let entries = read.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;\n",
)

needle = '''pub(crate) fn candidate_keys(\n'''
helper = '''fn list_in_read(read: &ReadTransaction) -> Result<Vec<(String, String)>, String> {\n    let table = read\n        .open_table(INDEX_DEFINITIONS)\n        .map_err(|e| e.to_string())?;\n    table\n        .iter()\n        .map_err(|e| e.to_string())?\n        .map(|item| {\n            item.map(|(name, field)| (name.value().to_string(), field.value().to_string()))\n                .map_err(|e| e.to_string())\n        })\n        .collect()\n}\n\npub(crate) fn candidate_keys(\n'''
replace_once("rust/src/index.rs", needle, helper)

# api.rs: create exactly one read transaction for the whole query execution.
old = '''        let spec = query::decode_query(&query_payload)?;\n        let (database, _) = db::database(&box_name)?;\n        let mut keys = match index::candidate_keys(&database, &spec.filter)? {\n            Some(keys) => keys,\n            None => db::all_keys(&box_name)?,\n        };\n        keys.sort();\n        keys.dedup();\n        let mut matched = 0usize;\n        let mut results = Vec::new();\n        for key in keys {\n            let Some(value) = db::get(&box_name, &key)? else {\n                continue;\n            };\n'''
new = '''        let spec = query::decode_query(&query_payload)?;\n        let (database, encryption) = db::database(&box_name)?;\n        let read = database.begin_read().map_err(|e| e.to_string())?;\n        let mut keys = match index::candidate_keys(&read, &spec.filter)? {\n            Some(keys) => keys,\n            None => db::query_all_keys(&read)?,\n        };\n        keys.sort();\n        keys.dedup();\n        let mut matched = 0usize;\n        let mut results = Vec::new();\n        for key in keys {\n            let Some(value) = db::query_get(&read, &encryption, &key)? else {\n                continue;\n            };\n'''
replace_once("rust/src/api.rs", old, new)
