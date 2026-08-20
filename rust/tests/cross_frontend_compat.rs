use std::sync::Mutex;

use rust_lib_dxtr_box::{api, DxtrBox};

static TEST_LOCK: Mutex<()> = Mutex::new(());

fn encoded_string(value: &str) -> Vec<u8> {
    rmp_serde::to_vec(value).expect("encode MessagePack fixture")
}

#[test]
fn rust_native_write_is_readable_through_frb_adapter() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let payload = encoded_string("written-by-rust-native");

    let db = DxtrBox::open(dir.path()).unwrap();
    let items = db.box_("cross_frontend_rust_to_frb").unwrap();
    items.put("shared", payload.clone()).unwrap();
    items.close().unwrap();

    let storage_file = dir.path().join("cross_frontend_rust_to_frb.dxtr");
    assert!(storage_file.is_file(), "both frontends must share one .dxtr file");

    api::init_db(dir.path().to_string_lossy().into_owned()).unwrap();
    api::open_box("cross_frontend_rust_to_frb".to_string(), None).unwrap();
    assert_eq!(
        api::get(
            "cross_frontend_rust_to_frb".to_string(),
            "shared".to_string()
        )
        .unwrap(),
        Some(payload)
    );
    api::close_box("cross_frontend_rust_to_frb".to_string()).unwrap();
}

#[test]
fn frb_adapter_write_is_readable_through_rust_native_frontend() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let payload = encoded_string("written-by-dart-frb-compatible-adapter");

    api::init_db(dir.path().to_string_lossy().into_owned()).unwrap();
    api::open_box("cross_frontend_frb_to_rust".to_string(), None).unwrap();
    api::put(
        "cross_frontend_frb_to_rust".to_string(),
        "shared".to_string(),
        payload.clone(),
    )
    .unwrap();
    api::close_box("cross_frontend_frb_to_rust".to_string()).unwrap();

    let storage_file = dir.path().join("cross_frontend_frb_to_rust.dxtr");
    assert!(storage_file.is_file(), "both frontends must share one .dxtr file");

    let db = DxtrBox::open(dir.path()).unwrap();
    let items = db.box_("cross_frontend_frb_to_rust").unwrap();
    assert_eq!(items.get("shared").unwrap(), Some(payload));
    items.close().unwrap();
}
