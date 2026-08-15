#![cfg(feature = "full")]

use std::io::Cursor;

use rmpv::Value;
use rust_lib_dxtr_box::{
    clear, close_box, create_index, drop_index, init_db, list_indexes, open_box, put, scan_query,
};

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

fn person(status: &str, age: i64) -> Vec<u8> {
    encode(&dxtr_map(vec![
        ("status", Value::from(status)),
        ("profile", dxtr_map(vec![("age", Value::from(age))])),
    ]))
}

fn query_payload() -> Vec<u8> {
    let age = dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from("profile.age")),
        ("operator", Value::from("greaterThanOrEqual")),
        ("value", Value::from(18_i64)),
        ("upperValue", Value::Nil),
    ]);
    let active = dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from("status")),
        ("operator", Value::from("equal")),
        ("value", Value::from("active")),
        ("upperValue", Value::Nil),
    ]);
    let group = dxtr_map(vec![
        ("type", Value::from("group")),
        ("operator", Value::from("and")),
        ("filters", Value::Array(vec![age, active])),
    ]);
    encode(&dxtr_map(vec![
        ("where", group),
        ("limit", Value::from(2_u64)),
        ("offset", Value::from(0_u64)),
    ]))
}

#[test]
fn native_scan_and_persisted_index_lifecycle() {
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("people".to_string(), None).unwrap();

    put(
        "people".to_string(),
        "charlie".to_string(),
        person("active", 40),
    )
    .unwrap();
    put(
        "people".to_string(),
        "alice".to_string(),
        person("active", 22),
    )
    .unwrap();
    put(
        "people".to_string(),
        "bob".to_string(),
        person("inactive", 35),
    )
    .unwrap();
    put(
        "people".to_string(),
        "teen".to_string(),
        person("active", 17),
    )
    .unwrap();

    let results = scan_query("people".to_string(), query_payload()).unwrap();
    assert_eq!(
        results
            .iter()
            .map(|record| record.key.as_str())
            .collect::<Vec<_>>(),
        vec!["alice", "charlie"]
    );

    create_index(
        "people".to_string(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .unwrap();
    let definitions = list_indexes("people".to_string()).unwrap();
    assert_eq!(definitions.len(), 1);
    assert_eq!(definitions[0].name, "by-status");
    assert_eq!(definitions[0].field, "status");

    close_box("people".to_string()).unwrap();
    open_box("people".to_string(), None).unwrap();
    assert_eq!(list_indexes("people".to_string()).unwrap().len(), 1);

    assert!(drop_index("people".to_string(), "by-status".to_string()).unwrap());
    assert!(list_indexes("people".to_string()).unwrap().is_empty());
    assert!(!drop_index("people".to_string(), "by-status".to_string()).unwrap());

    clear("people".to_string()).unwrap();
    close_box("people".to_string()).unwrap();
}

#[test]
fn encrypted_box_uses_scan_but_rejects_persisted_index_creation() {
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("secure".to_string(), Some("secret".to_string())).unwrap();
    put(
        "secure".to_string(),
        "one".to_string(),
        person("active", 30),
    )
    .unwrap();

    let results = scan_query("secure".to_string(), query_payload()).unwrap();
    assert_eq!(results.len(), 1);
    assert!(create_index(
        "secure".to_string(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .is_err());

    close_box("secure".to_string()).unwrap();
}

#[test]
fn query_payload_is_valid_messagepack() {
    let bytes = query_payload();
    let mut cursor = Cursor::new(bytes);
    assert!(rmpv::decode::read_value(&mut cursor).is_ok());
}
