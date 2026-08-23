#![cfg(feature = "full")]

use std::sync::Mutex;

use rust_lib_dxtr_box::{api, DxtrBox};

static TEST_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn rust_native_index_configuration_remains_dynamic_and_reopen_safe() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();

    let db = DxtrBox::open(dir.path()).unwrap();
    let box_ = db.box_("fingerprint_rust").unwrap();

    assert!(box_.list_indexes().unwrap().is_empty());
    box_.create_index("by-status", "status").unwrap();
    assert_eq!(
        box_.list_indexes().unwrap(),
        vec![rust_lib_dxtr_box::IndexDefinition {
            name: "by-status".to_string(),
            field: "status".to_string(),
        }]
    );
    box_.close().unwrap();

    let reopened = db.box_("fingerprint_rust").unwrap();
    assert_eq!(
        reopened.list_indexes().unwrap(),
        vec![rust_lib_dxtr_box::IndexDefinition {
            name: "by-status".to_string(),
            field: "status".to_string(),
        }]
    );
    assert!(reopened.drop_index("by-status").unwrap());
    reopened.close().unwrap();

    let reopened = db.box_("fingerprint_rust").unwrap();
    assert!(reopened.list_indexes().unwrap().is_empty());
    reopened.close().unwrap();
}

#[test]
fn frb_adapter_index_configuration_remains_dynamic_and_reopen_safe() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().to_string_lossy().into_owned();
    let box_name = "fingerprint_frb".to_string();

    api::init_db(path).unwrap();
    api::open_box(box_name.clone(), None).unwrap();
    assert!(api::list_indexes(box_name.clone()).unwrap().is_empty());

    api::create_index(
        box_name.clone(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .unwrap();
    let indexes = api::list_indexes(box_name.clone()).unwrap();
    assert_eq!(indexes.len(), 1);
    assert_eq!(indexes[0].name, "by-status");
    assert_eq!(indexes[0].field, "status");
    api::close_box(box_name.clone()).unwrap();

    api::open_box(box_name.clone(), None).unwrap();
    let indexes = api::list_indexes(box_name.clone()).unwrap();
    assert_eq!(indexes.len(), 1);
    assert_eq!(indexes[0].name, "by-status");
    assert_eq!(indexes[0].field, "status");
    assert!(api::drop_index(box_name.clone(), "by-status".to_string()).unwrap());
    api::close_box(box_name.clone()).unwrap();

    api::open_box(box_name.clone(), None).unwrap();
    assert!(api::list_indexes(box_name.clone()).unwrap().is_empty());
    api::close_box(box_name).unwrap();
}
