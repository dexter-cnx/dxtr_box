#![cfg(feature = "full")]

use std::sync::Mutex;

use rmpv::Value;
use rust_lib_dxtr_box::{DxtrBox, DxtrBoxError, SortOrder};

static TEST_LOCK: Mutex<()> = Mutex::new(());

fn encode(value: &Value) -> Vec<u8> {
    let mut bytes = Vec::new();
    rmpv::encode::write_value(&mut bytes, value).unwrap();
    bytes
}

fn dxtr_map(entries: Vec<(&str, Value)>) -> Value {
    Value::Array(vec![
        Value::from("@dxtr:map"),
        Value::Array(
            entries
                .into_iter()
                .map(|(key, value)| Value::Array(vec![Value::from(key), value]))
                .collect(),
        ),
    ])
}

fn asset(workplace_id: &str, captured_at: i64) -> Vec<u8> {
    encode(&dxtr_map(vec![
        ("workplace_id", Value::from(workplace_id)),
        ("captured_at", Value::from(captured_at)),
    ]))
}

#[test]
fn rust_native_crud_reopen_query_index_and_pagination() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();

    let db = DxtrBox::open(dir.path()).unwrap();
    let assets = db.box_("assets").unwrap();

    assets.put("a", asset("primary", 10)).unwrap();
    assets.put("b", asset("primary", 30)).unwrap();
    assets.put("c", asset("primary", 20)).unwrap();
    assets.put("other", asset("secondary", 40)).unwrap();

    assert_eq!(assets.len().unwrap(), 4);
    assert!(assets.contains_key("a").unwrap());
    assert!(assets.get("missing").unwrap().is_none());

    assets
        .create_index("workplace", "workplace_id")
        .unwrap();
    assert_eq!(assets.list_indexes().unwrap().len(), 1);

    let rows = assets
        .query()
        .where_("workplace_id")
        .equals("primary")
        .order_by("captured_at", SortOrder::Descending)
        .offset(1)
        .limit(2)
        .unwrap()
        .find()
        .unwrap();
    assert_eq!(rows.iter().map(|row| row.key.as_str()).collect::<Vec<_>>(), vec!["c", "a"]);

    assets.close().unwrap();
    let assets = db.box_("assets").unwrap();
    assert!(assets.get("b").unwrap().is_some());
    assert!(assets.drop_index("workplace").unwrap());
    assets.delete("other").unwrap();
    assert_eq!(assets.len().unwrap(), 3);
}

#[test]
fn rust_native_errors_are_structured() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    let db = DxtrBox::open(dir.path()).unwrap();
    let box_handle = db.box_("items").unwrap();

    let error = box_handle.put("", Vec::new()).unwrap_err();
    assert!(matches!(error, DxtrBoxError::InvalidInput { .. }));
}
