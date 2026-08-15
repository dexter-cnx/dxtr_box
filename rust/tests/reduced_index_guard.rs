#![cfg(not(feature = "full"))]

use redb::{Database, TableDefinition};
use rust_lib_dxtr_box::{init_db, open_box};

const DATA: TableDefinition<&str, &[u8]> = TableDefinition::new("data");
const META: TableDefinition<&str, &[u8]> = TableDefinition::new("meta");
const INDEX_DEFINITIONS: TableDefinition<&str, &str> = TableDefinition::new("index_definitions");

#[test]
fn reduced_profile_rejects_boxes_with_persisted_indexes() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("people.dxtr");
    let db = Database::create(&path).unwrap();
    let write = db.begin_write().unwrap();
    {
        write.open_table(DATA).unwrap();
        let mut meta = write.open_table(META).unwrap();
        meta.insert("format_version", b"dxtr_box/1".as_slice())
            .unwrap();
        meta.insert("encryption_mode", b"none".as_slice()).unwrap();
        let mut definitions = write.open_table(INDEX_DEFINITIONS).unwrap();
        definitions.insert("by-status", "status").unwrap();
    }
    write.commit().unwrap();
    drop(db);

    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    let error = open_box("people".to_string(), None).unwrap_err();
    assert!(error.contains("requires the full native profile"));
}
