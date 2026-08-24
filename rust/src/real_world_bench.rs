use std::{env, hint::black_box, time::Instant};

use rmpv::Value;

use crate::DxtrBox;

const DEFAULT_CATALOG_RECORDS: usize = 1_000;
const DEFAULT_ACTIVITY_RECORDS: usize = 2_000;
const DEFAULT_SAMPLES: usize = 5;
const BASE_TIMESTAMP_MS: i64 = 1_700_000_000_000;
const PAYLOAD_ALPHABET: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789";

#[test]
#[ignore = "purpose-built 0.10 Rust-native real-world diagnostic"]
fn rust_native_real_world_scenarios() {
    let catalog_records = env_usize("DXTR_BOX_REAL_WORLD_CATALOG", DEFAULT_CATALOG_RECORDS);
    let activity_records = env_usize("DXTR_BOX_REAL_WORLD_ACTIVITY", DEFAULT_ACTIVITY_RECORDS);
    let samples = env_usize("DXTR_BOX_REAL_WORLD_SAMPLES", DEFAULT_SAMPLES);
    assert!(catalog_records > 0);
    assert!(activity_records > 0);
    assert!(samples > 0);

    let temp = tempfile::tempdir().expect("create real-world benchmark temp dir");
    let db = DxtrBox::open(temp.path()).expect("open Rust-native database");

    run_settings(&db, samples);
    run_catalog(&db, catalog_records, samples);
    run_activity(&db, activity_records, samples);
}

fn run_settings(db: &DxtrBox, samples: usize) {
    let box_ = db.box_("rw_settings").expect("open settings box");
    box_.clear().expect("clear settings box");
    box_.put_all(settings_fixture())
        .expect("seed settings fixture");

    let mut elapsed = Vec::with_capacity(samples);
    for _ in 0..samples {
        let started = Instant::now();
        for iteration in 0..200 {
            black_box(box_.get("theme").expect("read theme"));
            black_box(box_.get("locale").expect("read locale"));
            black_box(box_.get("session").expect("read session"));
            box_.put(
                "active_workspace",
                encoded_map(vec![
                    ("value", Value::from(format!("workspace-{}", iteration % 5))),
                    ("updated_at", Value::from(1000 + iteration as i64)),
                ]),
            )
            .expect("update active workspace");
        }
        elapsed.push(started.elapsed().as_micros());
    }

    let active = box_
        .get("active_workspace")
        .expect("read final active workspace")
        .expect("active workspace exists");
    assert!(decode_map_string(&active, "value").as_deref() == Some("workspace-4"));

    emit_result("settings_session", 5, 800, &elapsed, "logical_records", 0);
    box_.close().expect("close settings box");
}

fn run_catalog(db: &DxtrBox, records: usize, samples: usize) {
    let box_ = db.box_("rw_catalog").expect("open catalog box");
    box_.clear().expect("clear catalog box");
    let fixture = catalog_fixture(records);
    box_.put_all(fixture.clone()).expect("seed catalog fixture");

    let hot_keys = (0..records.min(100)).map(catalog_key).collect::<Vec<_>>();
    let update_keys = hot_keys.iter().take(25).cloned().collect::<Vec<_>>();
    let delete_keys = (0..records)
        .step_by(20)
        .map(catalog_key)
        .collect::<Vec<_>>();

    let mut elapsed = Vec::with_capacity(samples);
    for _ in 0..samples {
        let started = Instant::now();
        let batch = box_.get_all(&hot_keys).expect("catalog batch read");
        for key in &update_keys {
            let raw = box_
                .get(key)
                .expect("catalog point read")
                .expect("catalog hot record exists");
            let score = decode_map_i64(&raw, "score").expect("catalog score");
            let id = decode_map_i64(&raw, "id").expect("catalog id");
            box_.put(
                key.clone(),
                encoded_catalog_record(id as usize, (score + 1) % 1000),
            )
            .expect("catalog update");
        }
        elapsed.push(started.elapsed().as_micros());

        assert_eq!(batch.len(), hot_keys.len());
        for (index, record) in batch.iter().enumerate() {
            assert_eq!(record.key, hot_keys[index]);
            assert_eq!(decode_map_i64(&record.value, "id"), Some(index as i64));
            let expected_name = format!("Asset {index:06}");
            assert_eq!(
                decode_map_string(&record.value, "name").as_deref(),
                Some(expected_name.as_str())
            );
        }
    }

    box_.delete_all(&delete_keys)
        .expect("delete catalog retention set");
    for key in &delete_keys {
        assert!(!box_.contains_key(key).expect("check deleted catalog key"));
    }

    let operations = hot_keys.len() + update_keys.len() * 2;
    emit_result(
        "catalog_workspace",
        records,
        operations,
        &elapsed,
        "logical_records",
        delete_keys.len(),
    );
    box_.close().expect("close catalog box");
}

fn run_activity(db: &DxtrBox, records: usize, samples: usize) {
    let box_ = db.box_("rw_activity").expect("open activity box");
    box_.clear().expect("clear activity box");
    box_.put_all(activity_fixture(records))
        .expect("seed activity fixture");

    let read_count = records.min(100);
    let delete_count = records / 4;
    let delete_keys = (0..delete_count).map(activity_key).collect::<Vec<_>>();

    let mut elapsed = Vec::with_capacity(samples);
    for _ in 0..samples {
        let started = Instant::now();
        for index in 0..read_count {
            let key = activity_key(records - 1 - index);
            black_box(box_.get(&key).expect("activity hot read"));
        }
        elapsed.push(started.elapsed().as_micros());
    }

    box_.delete_all(&delete_keys)
        .expect("delete activity retention window");
    for key in &delete_keys {
        assert!(!box_.contains_key(key).expect("check deleted activity key"));
    }
    if delete_count < records {
        let retained = activity_key(delete_count);
        assert!(box_
            .contains_key(&retained)
            .expect("check retained activity key"));
    }

    emit_result(
        "activity_event",
        records,
        read_count,
        &elapsed,
        "logical_records",
        delete_keys.len(),
    );
    box_.close().expect("close activity box");
}

fn settings_fixture() -> Vec<(String, Vec<u8>)> {
    vec![
        (
            "theme".into(),
            encoded_map(vec![
                ("value", Value::from("dark")),
                ("updated_at", Value::from(1)),
            ]),
        ),
        (
            "locale".into(),
            encoded_map(vec![
                ("value", Value::from("th_TH")),
                ("updated_at", Value::from(2)),
            ]),
        ),
        (
            "feature_flags".into(),
            encoded_map(vec![
                (
                    "value",
                    map_value(vec![
                        ("fast_search", Value::from(true)),
                        ("compact_cards", Value::from(false)),
                        ("offline_mode", Value::from(true)),
                    ]),
                ),
                ("updated_at", Value::from(3)),
            ]),
        ),
        (
            "active_workspace".into(),
            encoded_map(vec![
                ("value", Value::from("workspace-0003")),
                ("updated_at", Value::from(4)),
            ]),
        ),
        (
            "session".into(),
            encoded_map(vec![
                (
                    "value",
                    map_value(vec![
                        ("user_id", Value::from("user-local")),
                        ("last_route", Value::from("/workspace")),
                        ("launch_count", Value::from(42)),
                    ]),
                ),
                ("updated_at", Value::from(5)),
            ]),
        ),
    ]
}

fn catalog_fixture(records: usize) -> Vec<(String, Vec<u8>)> {
    (0..records)
        .map(|index| {
            (
                catalog_key(index),
                encoded_catalog_record(index, ((index * 37) % 1000) as i64),
            )
        })
        .collect()
}

fn encoded_catalog_record(index: usize, score: i64) -> Vec<u8> {
    encoded_map(vec![
        ("id", Value::from(index as i64)),
        ("name", Value::from(format!("Asset {index:06}"))),
        (
            "status",
            Value::from(if index.is_multiple_of(10) {
                "archived"
            } else {
                "active"
            }),
        ),
        ("category", Value::from(format!("category-{}", index % 8))),
        ("score", Value::from(score)),
        (
            "captured_at",
            Value::from(BASE_TIMESTAMP_MS + index as i64 * 1000),
        ),
        (
            "metadata",
            map_value(vec![
                (
                    "workspace_id",
                    Value::from(format!("workspace-{}", index % 5)),
                ),
                (
                    "source",
                    Value::from(if index.is_multiple_of(2) {
                        "camera"
                    } else {
                        "import"
                    }),
                ),
                ("favorite", Value::from(index.is_multiple_of(17))),
            ]),
        ),
        ("payload", Value::from(deterministic_payload(index, 192))),
    ])
}

fn activity_fixture(records: usize) -> Vec<(String, Vec<u8>)> {
    (0..records)
        .map(|index| {
            (
                activity_key(index),
                encoded_map(vec![
                    ("sequence", Value::from(index as i64)),
                    ("event_type", Value::from(event_type(index))),
                    (
                        "timestamp",
                        Value::from(BASE_TIMESTAMP_MS + index as i64 * 250),
                    ),
                    (
                        "actor",
                        map_value(vec![
                            ("id", Value::from(format!("actor-{}", index % 7))),
                            (
                                "source",
                                Value::from(if index.is_multiple_of(3) {
                                    "background"
                                } else {
                                    "foreground"
                                }),
                            ),
                        ]),
                    ),
                    (
                        "payload",
                        map_value(vec![
                            (
                                "target_id",
                                Value::from(format!("item-{:06}", index % 1000)),
                            ),
                            ("revision", Value::from((index % 13) as i64)),
                            ("note", Value::from(deterministic_payload(index, 48))),
                        ]),
                    ),
                ]),
            )
        })
        .collect()
}

fn event_type(index: usize) -> &'static str {
    match index % 4 {
        0 => "created",
        1 => "updated",
        2 => "viewed",
        _ => "synced_local",
    }
}

fn deterministic_payload(seed: usize, length: usize) -> String {
    (0..length)
        .map(|index| PAYLOAD_ALPHABET[(seed + index) % PAYLOAD_ALPHABET.len()] as char)
        .collect()
}

fn map_value(entries: Vec<(&str, Value)>) -> Value {
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

fn encoded_map(entries: Vec<(&str, Value)>) -> Vec<u8> {
    let value = map_value(entries);
    let mut bytes = Vec::new();
    rmpv::encode::write_value(&mut bytes, &value).expect("encode real-world record");
    bytes
}

fn decode_map_i64(bytes: &[u8], field: &str) -> Option<i64> {
    decode_map_field(bytes, field)?.as_i64()
}

fn decode_map_string(bytes: &[u8], field: &str) -> Option<String> {
    decode_map_field(bytes, field)?
        .as_str()
        .map(ToOwned::to_owned)
}

fn decode_map_field(bytes: &[u8], field: &str) -> Option<Value> {
    let mut cursor = std::io::Cursor::new(bytes);
    let value = rmpv::decode::read_value(&mut cursor).ok()?;
    let Value::Array(root) = value else {
        return None;
    };
    let Value::Array(entries) = root.get(1)? else {
        return None;
    };
    for entry in entries {
        let Value::Array(pair) = entry else { continue };
        if pair.first()?.as_str() == Some(field) {
            return pair.get(1).cloned();
        }
    }
    None
}

fn catalog_key(index: usize) -> String {
    format!("item-{index:06}")
}

fn activity_key(index: usize) -> String {
    format!("event-{index:08}")
}

fn emit_result(
    scenario: &str,
    records: usize,
    operations_per_sample: usize,
    elapsed_us: &[u128],
    operation_unit: &str,
    untimed_deleted: usize,
) {
    let mut ordered = elapsed_us.to_vec();
    ordered.sort_unstable();
    let median = ordered[ordered.len() / 2];
    let min = ordered[0];
    let max = ordered[ordered.len() - 1];
    println!(
        "DXTR_BOX_REAL_WORLD_RUST {{\"frontend\":\"rust_native\",\"scenario\":\"{scenario}\",\"records\":{records},\"samples\":{},\"operations_per_sample\":{operations_per_sample},\"operation_unit\":\"{operation_unit}\",\"elapsed_us\":{},\"median_us\":{median},\"min_us\":{min},\"max_us\":{max},\"rust_build_mode\":\"{}\",\"untimed_deleted\":{untimed_deleted}}}",
        elapsed_us.len(),
        json_u128_array(elapsed_us),
        if cfg!(debug_assertions) { "debug" } else { "release" },
    );
}

fn json_u128_array(values: &[u128]) -> String {
    let body = values
        .iter()
        .map(ToString::to_string)
        .collect::<Vec<_>>()
        .join(",");
    format!("[{body}]")
}

fn env_usize(name: &str, fallback: usize) -> usize {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(fallback)
}
