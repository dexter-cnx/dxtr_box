use std::{
    env,
    fs::{self, OpenOptions},
    hint::black_box,
    io::Write,
    path::Path,
    time::Instant,
};

use serde::{ser::SerializeSeq, Serialize, Serializer};

use crate::{core, db, query};

const DEFAULT_ITERATIONS: usize = 250;
const DEFAULT_SAMPLES: usize = 5;
const WARMUP_ITERATIONS: usize = 25;
const RECORD_COUNT: usize = 100;

struct BenchRecord {
    id: usize,
    group: usize,
    name: String,
    active: bool,
}

impl Serialize for BenchRecord {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut sequence = serializer.serialize_seq(Some(2))?;
        sequence.serialize_element("@dxtr:map")?;
        sequence.serialize_element(&BenchRecordEntries(self))?;
        sequence.end()
    }
}

struct BenchRecordEntries<'a>(&'a BenchRecord);

impl Serialize for BenchRecordEntries<'_> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut entries = serializer.serialize_seq(Some(4))?;
        entries.serialize_element(&("id", self.0.id))?;
        entries.serialize_element(&("group", self.0.group))?;
        entries.serialize_element(&("name", self.0.name.as_str()))?;
        entries.serialize_element(&("active", self.0.active))?;
        entries.end()
    }
}

#[test]
#[ignore = "purpose-built FRB read-boundary diagnostic"]
fn read_boundary_matrix_microbench() {
    let iterations = env_usize(
        "DXTR_BOX_READ_BOUNDARY_MATRIX_RUST_ITERATIONS",
        DEFAULT_ITERATIONS,
    );
    let samples = env_usize(
        "DXTR_BOX_READ_BOUNDARY_MATRIX_RUST_SAMPLES",
        DEFAULT_SAMPLES,
    );

    let temp = tempfile::tempdir().expect("create boundary matrix temp dir");
    db::init(temp.path().to_str().expect("utf-8 temp path")).expect("initialize database");
    db::open("read_boundary_matrix_rust", None).expect("open benchmark box");

    for i in 0..RECORD_COUNT {
        let value = rmp_serde::to_vec(&BenchRecord {
            id: i,
            group: i % 10,
            name: format!("record-{i}"),
            active: i % 2 == 0,
        })
        .expect("encode benchmark record");
        db::put("read_boundary_matrix_rust", &format!("record-{i}"), &value)
            .expect("seed benchmark record");
    }

    let batch10 = (0..10).map(|i| format!("record-{i}")).collect::<Vec<_>>();
    let batch100 = (0..RECORD_COUNT)
        .map(|i| format!("record-{i}"))
        .collect::<Vec<_>>();
    let query_spec = query::QuerySpec {
        filter: query::Filter::Comparison(query::Comparison {
            field: "group".to_string(),
            op: query::CompareOp::Equal,
            value: Some(rmpv::Value::from(3)),
            upper_value: None,
        }),
        sort_by: Vec::new(),
        limit: Some(10),
        offset: 0,
    };

    emit(&format!(
        "{{\"kind\":\"context\",\"layer\":\"rust_core\",\"os\":\"{}\",\"arch\":\"{}\",\"iterations\":{iterations},\"samples\":{samples},\"records\":{RECORD_COUNT}}}",
        env::consts::OS,
        env::consts::ARCH,
    ));

    measure("get_all_10", iterations, samples, || {
        black_box(core::get_all("read_boundary_matrix_rust", &batch10)?);
        Ok(())
    });
    measure("get_all_100", iterations, samples, || {
        black_box(core::get_all("read_boundary_matrix_rust", &batch100)?);
        Ok(())
    });
    measure("query_equal_limit_10", iterations, samples, || {
        black_box(core::query("read_boundary_matrix_rust", &query_spec)?);
        Ok(())
    });

    db::close("read_boundary_matrix_rust");
}

fn measure<F>(operation: &str, iterations: usize, samples: usize, mut action: F)
where
    F: FnMut() -> Result<(), String>,
{
    for _ in 0..WARMUP_ITERATIONS {
        action().expect("boundary matrix warmup");
    }

    let mut sample_ns = Vec::with_capacity(samples);
    for _ in 0..samples {
        let started = Instant::now();
        for _ in 0..iterations {
            action().expect("boundary matrix iteration");
        }
        sample_ns.push(started.elapsed().as_nanos());
    }
    sample_ns.sort_unstable();
    let median_total_ns = median_u128(&sample_ns);
    let median_ns_per_op = median_total_ns as f64 / iterations as f64;
    emit(&format!(
        "{{\"kind\":\"measurement\",\"layer\":\"rust_core\",\"operation\":\"{operation}\",\"iterations\":{iterations},\"samples\":{samples},\"sample_ns\":{},\"median_ns_per_op\":{median_ns_per_op:.3}}}",
        json_u128_array(&sample_ns),
    ));
}

fn emit(line: &str) {
    println!("DXTR_BOX_READ_BOUNDARY_MATRIX_RUST {line}");
    let Some(output) = env::var_os("DXTR_BOX_READ_BOUNDARY_MATRIX_RUST_OUTPUT") else {
        return;
    };
    let path = Path::new(&output);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create Rust boundary matrix output directory");
    }
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .expect("open Rust boundary matrix output");
    writeln!(file, "{line}").expect("write Rust boundary matrix output");
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
