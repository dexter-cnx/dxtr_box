#![cfg(feature = "full")]

use std::{io::Cursor, sync::Mutex};

use rmpv::Value;
use rust_lib_dxtr_box::{
    clear, close_box, create_index, drop_index, init_db, list_indexes, open_box, put, scan_query,
};

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
    let _guard = TEST_LOCK.lock().unwrap();
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

    let indexed_results = scan_query("people".to_string(), query_payload()).unwrap();
    assert_eq!(
        indexed_results
            .iter()
            .map(|record| record.key.as_str())
            .collect::<Vec<_>>(),
        vec!["alice", "charlie"]
    );
    assert_eq!(
        indexed_results
            .iter()
            .map(|record| record.value.as_slice())
            .collect::<Vec<_>>(),
        results
            .iter()
            .map(|record| record.value.as_slice())
            .collect::<Vec<_>>()
    );

    put(
        "people".to_string(),
        "alice".to_string(),
        person("inactive", 22),
    )
    .unwrap();
    let after_indexed_mutation = scan_query("people".to_string(), query_payload()).unwrap();
    assert_eq!(
        after_indexed_mutation
            .iter()
            .map(|record| record.key.as_str())
            .collect::<Vec<_>>(),
        vec!["charlie"]
    );

    close_box("people".to_string()).unwrap();
    open_box("people".to_string(), None).unwrap();
    assert_eq!(list_indexes("people".to_string()).unwrap().len(), 1);

    assert!(drop_index("people".to_string(), "by-status".to_string()).unwrap());
    assert!(list_indexes("people".to_string()).unwrap().is_empty());
    assert!(!drop_index("people".to_string(), "by-status".to_string()).unwrap());

    clear("people".to_string()).unwrap();
    close_box("people".to_string()).unwrap();
}

fn comparison_query(field: &str, operator: &str, value: Value, upper: Value) -> Vec<u8> {
    let comparison = dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from(field)),
        ("operator", Value::from(operator)),
        ("value", value),
        ("upperValue", upper),
    ]);
    encode(&dxtr_map(vec![
        ("where", comparison),
        ("limit", Value::Nil),
        ("offset", Value::from(0_u64)),
    ]))
}

fn result_keys(box_name: &str, payload: Vec<u8>) -> Vec<String> {
    scan_query(box_name.to_string(), payload)
        .unwrap()
        .into_iter()
        .map(|record| record.key)
        .collect()
}

#[test]
fn nested_range_index_matches_scan_for_all_ordered_operators() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("ages".to_string(), None).unwrap();

    for (key, age) in [("a", 17), ("b", 18), ("c", 22), ("d", 40), ("e", 65)] {
        put("ages".to_string(), key.to_string(), person("active", age)).unwrap();
    }

    let queries = vec![
        comparison_query(
            "profile.age",
            "greaterThan",
            Value::from(18_i64),
            Value::Nil,
        ),
        comparison_query(
            "profile.age",
            "greaterThanOrEqual",
            Value::from(18_i64),
            Value::Nil,
        ),
        comparison_query("profile.age", "lessThan", Value::from(40_i64), Value::Nil),
        comparison_query(
            "profile.age",
            "lessThanOrEqual",
            Value::from(40_i64),
            Value::Nil,
        ),
        comparison_query(
            "profile.age",
            "between",
            Value::from(18_i64),
            Value::from(40_i64),
        ),
    ];
    let scan_results = queries
        .iter()
        .cloned()
        .map(|payload| result_keys("ages", payload))
        .collect::<Vec<_>>();

    create_index(
        "ages".to_string(),
        "by-age".to_string(),
        "profile.age".to_string(),
    )
    .unwrap();

    let indexed_results = queries
        .into_iter()
        .map(|payload| result_keys("ages", payload))
        .collect::<Vec<_>>();
    assert_eq!(indexed_results, scan_results);

    close_box("ages".to_string()).unwrap();
}

#[test]
fn and_group_intersects_multiple_persisted_indexes() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("intersection".to_string(), None).unwrap();

    for (key, status, age) in [
        ("alice", "active", 22),
        ("bob", "inactive", 35),
        ("charlie", "active", 40),
        ("teen", "active", 17),
    ] {
        put(
            "intersection".to_string(),
            key.to_string(),
            person(status, age),
        )
        .unwrap();
    }

    let scan = result_keys("intersection", query_payload());
    create_index(
        "intersection".to_string(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .unwrap();
    create_index(
        "intersection".to_string(),
        "by-age".to_string(),
        "profile.age".to_string(),
    )
    .unwrap();

    let indexed = result_keys("intersection", query_payload());
    assert_eq!(indexed, scan);
    assert_eq!(indexed, vec!["alice", "charlie"]);

    close_box("intersection".to_string()).unwrap();
}

#[test]
fn encrypted_box_uses_scan_but_rejects_persisted_index_creation() {
    let _guard = TEST_LOCK.lock().unwrap();
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

fn sorted_query_payload(
    filter: (&str, &str, Value),
    sort: (&str, &str, &str),
    limit: Option<u64>,
    offset: u64,
) -> Vec<u8> {
    let (filter_field, filter_operator, filter_value) = filter;
    let (sort_field, direction, nulls) = sort;
    let comparison = dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from(filter_field)),
        ("operator", Value::from(filter_operator)),
        ("value", filter_value),
        ("upperValue", Value::Nil),
    ]);
    let sort = dxtr_map(vec![
        ("field", Value::from(sort_field)),
        ("direction", Value::from(direction)),
        ("nulls", Value::from(nulls)),
    ]);
    encode(&dxtr_map(vec![
        ("where", comparison),
        ("sortBy", Value::Array(vec![sort])),
        ("limit", limit.map(Value::from).unwrap_or(Value::Nil)),
        ("offset", Value::from(offset)),
    ]))
}

#[test]
fn explicit_sort_orders_before_pagination_and_matches_index_execution() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("sorted".to_string(), None).unwrap();

    for (key, age) in [("a", 22), ("b", 40), ("c", 22), ("d", 17)] {
        put("sorted".to_string(), key.to_string(), person("active", age)).unwrap();
    }

    let payload = sorted_query_payload(
        ("profile.age", "greaterThanOrEqual", Value::from(0_i64)),
        ("profile.age", "descending", "last"),
        Some(2),
        1,
    );
    let scan = result_keys("sorted", payload.clone());
    assert_eq!(scan, vec!["a", "c"]);

    create_index(
        "sorted".to_string(),
        "by-age".to_string(),
        "profile.age".to_string(),
    )
    .unwrap();
    let indexed = result_keys("sorted", payload);
    assert_eq!(indexed, scan);

    close_box("sorted".to_string()).unwrap();
}

#[test]
fn explicit_sort_treats_missing_and_null_as_one_nullish_category() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("null_sort".to_string(), None).unwrap();

    put(
        "null_sort".to_string(),
        "a".to_string(),
        person("active", 22),
    )
    .unwrap();
    put(
        "null_sort".to_string(),
        "b".to_string(),
        encode(&dxtr_map(vec![
            ("status", Value::from("active")),
            ("profile", dxtr_map(vec![("age", Value::Nil)])),
        ])),
    )
    .unwrap();
    put(
        "null_sort".to_string(),
        "c".to_string(),
        encode(&dxtr_map(vec![("status", Value::from("active"))])),
    )
    .unwrap();
    put(
        "null_sort".to_string(),
        "d".to_string(),
        person("active", 40),
    )
    .unwrap();

    let payload = sorted_query_payload(
        ("status", "isNotNull", Value::Nil),
        ("profile.age", "ascending", "first"),
        None,
        0,
    );
    assert_eq!(result_keys("null_sort", payload), vec!["b", "c", "a", "d"]);

    close_box("null_sort".to_string()).unwrap();
}

#[test]
fn explicit_sort_rejects_mixed_non_null_ordered_types() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("mixed_sort".to_string(), None).unwrap();

    put(
        "mixed_sort".to_string(),
        "a".to_string(),
        person("active", 22),
    )
    .unwrap();
    put(
        "mixed_sort".to_string(),
        "b".to_string(),
        encode(&dxtr_map(vec![
            ("status", Value::from("active")),
            ("profile", dxtr_map(vec![("age", Value::from("22"))])),
        ])),
    )
    .unwrap();

    let payload = sorted_query_payload(
        ("status", "isNotNull", Value::Nil),
        ("profile.age", "ascending", "last"),
        None,
        0,
    );
    let error = match scan_query("mixed_sort".to_string(), payload) {
        Ok(_) => panic!("mixed ordered sort types must be rejected"),
        Err(error) => error,
    };
    assert!(error.contains("mixes incompatible"));

    close_box("mixed_sort".to_string()).unwrap();
}

#[test]
fn explicit_sort_preserves_large_integer_precision() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("precise_sort".to_string(), None).unwrap();

    put(
        "precise_sort".to_string(),
        "higher".to_string(),
        person("active", 9_007_199_254_740_993_i64),
    )
    .unwrap();
    put(
        "precise_sort".to_string(),
        "lower".to_string(),
        person("active", 9_007_199_254_740_992_i64),
    )
    .unwrap();

    let payload = sorted_query_payload(
        ("status", "isNotNull", Value::Nil),
        ("profile.age", "ascending", "last"),
        None,
        0,
    );
    assert_eq!(
        result_keys("precise_sort", payload),
        vec!["lower", "higher"]
    );

    close_box("precise_sort".to_string()).unwrap();
}

#[test]
fn query_payload_is_valid_messagepack() {
    let _guard = TEST_LOCK.lock().unwrap();
    let bytes = query_payload();
    let mut cursor = Cursor::new(bytes);
    assert!(rmpv::decode::read_value(&mut cursor).is_ok());
}
