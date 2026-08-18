#![cfg(not(feature = "full"))]

use std::sync::Mutex;

use rust_lib_dxtr_box::{DxtrBox, DxtrBoxError};

static TEST_LOCK: Mutex<()> = Mutex::new(());

#[test]
fn reduced_profile_indexes_report_unsupported_feature() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let box_handle = db.box_("items").unwrap();

    let create = box_handle.create_index("by_value", "value").unwrap_err();
    assert!(matches!(create, DxtrBoxError::UnsupportedFeature { .. }));

    let list = box_handle.list_indexes().unwrap_err();
    assert!(matches!(list, DxtrBoxError::UnsupportedFeature { .. }));

    let drop_error = box_handle.drop_index("by_value").unwrap_err();
    assert!(matches!(drop_error, DxtrBoxError::UnsupportedFeature { .. }));

    box_handle.close().unwrap();
}
