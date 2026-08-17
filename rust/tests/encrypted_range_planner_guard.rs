#![cfg(feature = "full")]

use std::sync::Mutex;

use redb::{Database, ReadableTable, TableDefinition};
use rmpv::Value;
use rust_lib_dxtr_box::{close_box, create_index, init_db, open_box, put, scan_query};

static TEST_LOCK: Mutex<()> = Mutex::new(());
const INDEX_ENTRIES: TableDefinition<&[u8], &[u8]> = TableDefinition::new("index_entries");

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

fn entry_index_name(key: &[u8]) -> Option<&[u8]> {
    let length_bytes = key.get(..4)?;
    let length = u32::from_be_bytes(length_bytes.try_into().ok()?) as usize;
    key.get(4..4 + length)
}

fn remove_index_entries(db_path: &std::path::Path, index_name: &str) {
    let db = Database::open(db_path).unwrap();
    let write = db.begin_write().unwrap();
    {
        let mut entries = write.open_table(INDEX_ENTRIES).unwrap();
        let matching = entries
            .iter()
            .unwrap()
            .map(|item| item.unwrap().0.value().to_vec())
            .filter(|key| entry_index_name(key) == Some(index_name.as_bytes()))
            .collect::<Vec<_>>();
        for key in matching {
            entries.remove(key.as_slice()).unwrap();
        }
    }
    write.commit().unwrap();
}

#[test]
fn encrypted_range_planner_does_not_depend_on_range_index_entries() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("secure-planner".to_string(), Some("secret".to_string())).unwrap();

    for (key, status, age) in [
        ("a", "active", 17),
        ("b", "active", 22),
        ("c", "inactive", 30),
        ("d", "active", 40),
        ("e", "active", 65),
    ] {
        put(
            "secure-planner".to_string(),
            key.to_string(),
            person(status, age),
        )
        .unwrap();
    }

    create_index(
        "secure-planner".to_string(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .unwrap();
    create_index(
        "secure-planner".to_string(),
        "by-age".to_string(),
        "age".to_string(),
    )
    .unwrap();

    let pure_range = query(comparison(
        "age",
        "greaterThanOrEqual",
        Value::from(40_i64),
        Value::Nil,
    ));
    let mixed_and = query(dxtr_map(vec![
        ("type", Value::from("group")),
        ("operator", Value::from("and")),
        (
            "filters",
            Value::Array(vec![
                comparison("status", "equal", Value::from("active"), Value::Nil),
                comparison("age", "greaterThanOrEqual", Value::from(22_i64), Value::Nil),
            ]),
        ),
    ]));

    assert_eq!(
        keys("secure-planner", pure_range.clone()),
        vec!["d", "e"]
    );
    assert_eq!(
        keys("secure-planner", mixed_and.clone()),
        vec!["b", "d", "e"]
    );

    close_box("secure-planner".to_string()).unwrap();

    remove_index_entries(&dir.path().join("secure-planner.dxtr"), "by-age");

    open_box("secure-planner".to_string(), Some("secret".to_string())).unwrap();

    // If encrypted range planning starts consuming `by-age`, deleting its derived
    // entries above makes these assertions fail. Equality narrowing through
    // `by-status` remains intact for the mixed AND case.
    assert_eq!(keys("secure-planner", pure_range), vec!["d", "e"]);
    assert_eq!(keys("secure-planner", mixed_and), vec!["b", "d", "e"]);

    close_box("secure-planner".to_string()).unwrap();
}
