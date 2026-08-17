#![cfg(feature = "full")]

use std::{io::Cursor, sync::Mutex};

use rmpv::Value;
use rust_lib_dxtr_box::{close_box, create_index, init_db, open_box, put, scan_query};

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

fn person(status: &str, age: i64) -> Vec<u8> {
    encode(&dxtr_map(vec![
        ("status", Value::from(status)),
        ("age", Value::from(age)),
    ]))
}

fn comparison(field: &str, operator: &str, value: Value, upper: Value) -> Value {
    dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from(field)),
        ("operator", Value::from(operator)),
        ("value", value),
        ("upperValue", upper),
    ])
}

fn query(filter: Value) -> Vec<u8> {
    encode(&dxtr_map(vec![
        ("where", filter),
        ("limit", Value::Nil),
        ("offset", Value::from(0_u64)),
    ]))
}

fn keys(box_name: &str, payload: Vec<u8>) -> Vec<String> {
    scan_query(box_name.to_string(), payload)
        .unwrap()
        .into_iter()
        .map(|record| record.key)
        .collect()
}

#[test]
fn encrypted_ordered_predicates_remain_scan_equivalent_after_index_creation() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("secure-range".to_string(), Some("secret".to_string())).unwrap();

    for (key, status, age) in [
        ("a", "active", 17),
        ("b", "active", 18),
        ("c", "inactive", 22),
        ("d", "active", 40),
        ("e", "active", 65),
    ] {
        put(
            "secure-range".to_string(),
            key.to_string(),
            person(status, age),
        )
        .unwrap();
    }

    let ordered_queries = vec![
        query(comparison(
            "age",
            "greaterThan",
            Value::from(18_i64),
            Value::Nil,
        )),
        query(comparison(
            "age",
            "greaterThanOrEqual",
            Value::from(18_i64),
            Value::Nil,
        )),
        query(comparison(
            "age",
            "lessThan",
            Value::from(40_i64),
            Value::Nil,
        )),
        query(comparison(
            "age",
            "lessThanOrEqual",
            Value::from(40_i64),
            Value::Nil,
        )),
        query(comparison(
            "age",
            "between",
            Value::from(18_i64),
            Value::from(40_i64),
        )),
    ];

    let scan_results = ordered_queries
        .iter()
        .cloned()
        .map(|payload| keys("secure-range", payload))
        .collect::<Vec<_>>();

    create_index(
        "secure-range".to_string(),
        "by-age".to_string(),
        "age".to_string(),
    )
    .unwrap();

    let after_index_results = ordered_queries
        .into_iter()
        .map(|payload| keys("secure-range", payload))
        .collect::<Vec<_>>();

    assert_eq!(after_index_results, scan_results);
    close_box("secure-range".to_string()).unwrap();
}

#[test]
fn encrypted_mixed_and_uses_equality_narrowing_without_changing_range_semantics() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("secure-mixed".to_string(), Some("secret".to_string())).unwrap();

    for (key, status, age) in [
        ("a", "active", 17),
        ("b", "active", 22),
        ("c", "inactive", 30),
        ("d", "active", 40),
        ("e", "active", 65),
    ] {
        put(
            "secure-mixed".to_string(),
            key.to_string(),
            person(status, age),
        )
        .unwrap();
    }

    let filter = dxtr_map(vec![
        ("type", Value::from("group")),
        ("operator", Value::from("and")),
        (
            "filters",
            Value::Array(vec![
                comparison("status", "equal", Value::from("active"), Value::Nil),
                comparison(
                    "age",
                    "greaterThanOrEqual",
                    Value::from(22_i64),
                    Value::Nil,
                ),
            ]),
        ),
    ]);
    let payload = query(filter);
    let scan = keys("secure-mixed", payload.clone());

    create_index(
        "secure-mixed".to_string(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .unwrap();
    create_index(
        "secure-mixed".to_string(),
        "by-age".to_string(),
        "age".to_string(),
    )
    .unwrap();

    let indexed = keys("secure-mixed", payload);
    assert_eq!(indexed, scan);
    assert_eq!(indexed, vec!["b", "d", "e"]);

    close_box("secure-mixed".to_string()).unwrap();
}
