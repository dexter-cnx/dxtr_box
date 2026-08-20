use std::{
    env,
    fs::{self, OpenOptions},
    hint::black_box,
    io::Write,
    path::Path,
    time::Instant,
};

use rmpv::Value;

use crate::{DxtrBox, SortOrder};

const DEFAULT_ITERATIONS: usize = 200;
const DEFAULT_SAMPLES: usize = 5;
const DEFAULT_RECORDS: usize = 1_000;
const WARMUP_ITERATIONS: usize = 20;

#[test]
#[ignore = "purpose-built 0.8 multi-frontend diagnostic; run through make benchmark-multi-frontend"]
fn rust_native_frontend_benchmark() {
    let iterations = env_usize(
        "DXTR_BOX_MULTI_FRONTEND_RUST_ITERATIONS",
        DEFAULT_ITERATIONS,
    );
    let samples = env_usize("DXTR_BOX_MULTI_FRONTEND_RUST_SAMPLES", DEFAULT_SAMPLES);
    let records = env_usize("DXTR_BOX_MULTI_FRONTEND_RECORDS", DEFAULT_RECORDS);
    assert!(iterations > 0);
    assert!(samples > 0);
    assert!(records >= 100);

    let temp = tempfile::tempdir().expect("create multi-frontend benchmark temp dir");
    let db = DxtrBox::open(temp.path()).expect("open Rust-native database");
    let items = db.box_("multi_frontend").expect("open benchmark box");

    let entries = (0..records)
        .map(|index| {
            let group = if index % 4 == 0 { "target" } else { "other" };
            (
                format!("item-{index:05}"),
                encoded_record(index as i64, group),
            )
        })
        .collect::<Vec<_>>();
    items.put_all(entries).expect("seed benchmark records");
    items
        .create_index("by_group", "group")
        .expect("create benchmark equality index");

    let point_key = format!("item-{:05}", records / 2);
    let batch_keys = (0..100.min(records))
        .map(|index| format!("item-{index:05}"))
        .collect::<Vec<_>>();

    emit_context(iterations, samples, records);

    measure("get", iterations, samples, || {
        black_box(items.get(black_box(&point_key))?);
        Ok(())
    });

    measure("get_all_100", iterations, samples, || {
        black_box(items.get_all(black_box(&batch_keys))?);
        Ok(())
    });

    measure("indexed_query_sort_limit", iterations, samples, || {
        let rows = items
            .query()
            .where_("group")
            .equals("target")
            .order_by("score", SortOrder::Descending)
            .limit(50)
            .find()?;
        black_box(rows);
        Ok(())
    });

    items.close().expect("close benchmark box");
}

fn encoded_record(score: i64, group: &str) -> Vec<u8> {
    let value = Value::Array(vec![
        Value::from("@dxtr:map"),
        Value::Array(vec![
            Value::Array(vec![Value::from("score"), Value::from(score)]),
            Value::Array(vec![Value::from("group"), Value::from(group)]),
            Value::Array(vec![Value::from("payload"), Value::from("x".repeat(128))]),
        ]),
    ]);
    let mut bytes = Vec::new();
    rmpv::encode::write_value(&mut bytes, &value).expect("encode benchmark record");
    bytes
}

fn measure<F>(operation: &str, iterations: usize, samples: usize, mut action: F)
where
    F: FnMut() -> Result<(), crate::DxtrBoxError>,
{
    for _ in 0..WARMUP_ITERATIONS {
        action().expect("multi-frontend benchmark warmup");
    }

    let mut sample_ns = Vec::with_capacity(samples);
    for _ in 0..samples {
        let started = Instant::now();
        for _ in 0..iterations {
            action().expect("multi-frontend benchmark iteration");
        }
        sample_ns.push(started.elapsed().as_nanos());
    }
    sample_ns.sort_unstable();
    let median_total_ns = median_u128(&sample_ns);
    let median_ns_per_op = median_total_ns as f64 / iterations as f64;
    emit(&format!(
        "{{\"kind\":\"measurement\",\"frontend\":\"rust-native\",\"operation\":\"{operation}\",\"iterations\":{iterations},\"samples\":{samples},\"sample_ns\":{},\"median_ns_per_op\":{median_ns_per_op:.3}}}",
        json_u128_array(&sample_ns),
    ));
}

fn emit_context(iterations: usize, samples: usize, records: usize) {
    emit(&format!(
        "{{\"kind\":\"context\",\"frontend\":\"rust-native\",\"os\":\"{}\",\"arch\":\"{}\",\"iterations\":{iterations},\"samples\":{samples},\"records\":{records}}}",
        env::consts::OS,
        env::consts::ARCH,
    ));
}

fn emit(line: &str) {
    println!("DXTR_BOX_MULTI_FRONTEND_RUST {line}");
    let Some(output) = env::var_os("DXTR_BOX_MULTI_FRONTEND_RUST_OUTPUT") else {
        return;
    };
    let path = Path::new(&output);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create benchmark output directory");
    }
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("open Rust benchmark output");
    writeln!(file, "{line}").expect("write Rust benchmark output");
}

fn env_usize(name: &str, fallback: usize) -> usize {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(fallback)
}

fn median_u128(ordered: &[u128]) -> u128 {
    let middle = ordered.len() / 2;
    if ordered.len() % 2 == 1 {
        ordered[middle]
    } else {
        (ordered[middle - 1] + ordered[middle]) / 2
    }
}

fn json_u128_array(values: &[u128]) -> String {
    let mut output = String::from("[");
    for (index, value) in values.iter().enumerate() {
        if index > 0 {
            output.push(',');
        }
        output.push_str(&value.to_string());
    }
    output.push(']');
    output
}
