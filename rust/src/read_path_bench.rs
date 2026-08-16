use std::{
    env,
    fs::{self, OpenOptions},
    hint::black_box,
    io::Write,
    path::Path,
    time::Instant,
};

use serde::{
    ser::{SerializeSeq, Serializer},
    Serialize,
};

#[cfg(feature = "encryption")]
use crate::crypto;
use crate::{codec::validate_message_pack, db};

const DEFAULT_ITERATIONS: usize = 2_000;
const DEFAULT_SAMPLES: usize = 7;
const WARMUP_ITERATIONS: usize = 100;

struct BenchPayload {
    id: u64,
    label: String,
    body: String,
}

/// Serialize the benchmark record using the same logical wire shape as
/// `DxtrCodec.encode(Map<String, dynamic>)`:
///
/// ["@dxtr:map", [["id", id], ["label", label], ["body", body]]]
impl Serialize for BenchPayload {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut sequence = serializer.serialize_seq(Some(2))?;
        sequence.serialize_element("@dxtr:map")?;
        sequence.serialize_element(&BenchPayloadEntries(self))?;
        sequence.end()
    }
}

struct BenchPayloadEntries<'a>(&'a BenchPayload);

impl Serialize for BenchPayloadEntries<'_> {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut entries = serializer.serialize_seq(Some(3))?;
        entries.serialize_element(&("id", self.0.id))?;
        entries.serialize_element(&("label", self.0.label.as_str()))?;
        entries.serialize_element(&("body", self.0.body.as_str()))?;
        entries.end()
    }
}

#[test]
#[ignore = "purpose-built 0.5 diagnostic; run through make benchmark-read-path"]
fn read_path_microbench() {
    let iterations = env_usize("DXTR_BOX_READ_PATH_RUST_ITERATIONS", DEFAULT_ITERATIONS);
    let samples = env_usize("DXTR_BOX_READ_PATH_RUST_SAMPLES", DEFAULT_SAMPLES);
    assert!(iterations > 0);
    assert!(samples > 0);

    let temp = tempfile::tempdir().expect("create read-path benchmark temp dir");
    db::init(temp.path().to_str().expect("utf-8 temp path")).expect("initialize database");
    db::open("read_path_plain", None).expect("open plaintext box");

    #[cfg(feature = "encryption")]
    db::open("read_path_encrypted", Some("dxtr-box-read-path-benchmark"))
        .expect("open encrypted box");

    let payloads = [
        ("small", encoded_payload(1, 64)),
        ("medium", encoded_payload(2, 4096)),
    ];

    emit_context(iterations, samples);

    for (size_name, payload) in &payloads {
        let key = format!("{size_name}-hit");
        let miss_key = format!("{size_name}-missing");
        db::put("read_path_plain", &key, payload).expect("seed plaintext payload");
        #[cfg(feature = "encryption")]
        db::put("read_path_encrypted", &key, payload).expect("seed encrypted payload");

        let (plain_db, _) = db::database("read_path_plain").expect("plaintext database handle");

        measure(
            "redb_read_transaction_create",
            size_name,
            "plaintext",
            "n/a",
            iterations,
            samples,
            || {
                let read = plain_db.begin_read().map_err(|error| error.to_string())?;
                black_box(read);
                Ok(())
            },
        );

        measure(
            "redb_read_transaction_open_table",
            size_name,
            "plaintext",
            "n/a",
            iterations,
            samples,
            || {
                let read = plain_db.begin_read().map_err(|error| error.to_string())?;
                let table = read
                    .open_table(db::DATA)
                    .map_err(|error| error.to_string())?;
                black_box(table);
                Ok(())
            },
        );

        {
            let read = plain_db.begin_read().expect("open stable read snapshot");
            let table = read.open_table(db::DATA).expect("open data table");
            measure(
                "redb_point_lookup_borrowed",
                size_name,
                "plaintext",
                "hit",
                iterations,
                samples,
                || {
                    let value = table.get(key.as_str()).map_err(|error| error.to_string())?;
                    black_box(value.as_ref().map(|guard| guard.value().len()));
                    Ok(())
                },
            );
            measure(
                "redb_point_lookup_borrowed",
                size_name,
                "plaintext",
                "miss",
                iterations,
                samples,
                || {
                    let value = table
                        .get(miss_key.as_str())
                        .map_err(|error| error.to_string())?;
                    black_box(value.is_some());
                    Ok(())
                },
            );
            measure(
                "redb_point_lookup_copy",
                size_name,
                "plaintext",
                "hit",
                iterations,
                samples,
                || {
                    let value = table
                        .get(key.as_str())
                        .map_err(|error| error.to_string())?
                        .expect("seeded key");
                    black_box(value.value().to_vec());
                    Ok(())
                },
            );
        }

        measure(
            "messagepack_validate",
            size_name,
            "plaintext",
            "hit",
            iterations,
            samples,
            || {
                validate_message_pack(black_box(payload))?;
                Ok(())
            },
        );

        measure(
            "vec_payload_copy",
            size_name,
            "plaintext",
            "hit",
            iterations,
            samples,
            || {
                black_box(payload.to_vec());
                Ok(())
            },
        );

        measure(
            "db_get",
            size_name,
            "plaintext",
            "hit",
            iterations,
            samples,
            || {
                black_box(db::get("read_path_plain", &key)?);
                Ok(())
            },
        );
        measure(
            "db_get",
            size_name,
            "plaintext",
            "miss",
            iterations,
            samples,
            || {
                black_box(db::get("read_path_plain", &miss_key)?);
                Ok(())
            },
        );
        measure(
            "db_contains_key",
            size_name,
            "plaintext",
            "hit",
            iterations,
            samples,
            || {
                black_box(db::contains_key("read_path_plain", &key)?);
                Ok(())
            },
        );
        measure(
            "db_contains_key",
            size_name,
            "plaintext",
            "miss",
            iterations,
            samples,
            || {
                black_box(db::contains_key("read_path_plain", &miss_key)?);
                Ok(())
            },
        );

        #[cfg(feature = "encryption")]
        {
            let crypto_key = [0x5au8; 32];
            let ciphertext = crypto::encrypt_with_aad(&crypto_key, key.as_bytes(), payload)
                .expect("prepare encrypted payload");
            measure(
                "decrypt_authenticate",
                size_name,
                "encrypted",
                "hit",
                iterations,
                samples,
                || {
                    let plaintext = crypto::decrypt_with_aad(
                        black_box(&crypto_key),
                        black_box(key.as_bytes()),
                        black_box(&ciphertext),
                    )
                    .map_err(|error| error.to_string())?;
                    black_box(plaintext);
                    Ok(())
                },
            );
            measure(
                "db_get",
                size_name,
                "encrypted",
                "hit",
                iterations,
                samples,
                || {
                    black_box(db::get("read_path_encrypted", &key)?);
                    Ok(())
                },
            );
            measure(
                "db_get",
                size_name,
                "encrypted",
                "miss",
                iterations,
                samples,
                || {
                    black_box(db::get("read_path_encrypted", &miss_key)?);
                    Ok(())
                },
            );
        }
    }

    db::close("read_path_plain");
    #[cfg(feature = "encryption")]
    db::close("read_path_encrypted");
}

fn encoded_payload(id: u64, body_len: usize) -> Vec<u8> {
    rmp_serde::to_vec(&BenchPayload {
        id,
        label: format!("record-{id}"),
        body: "x".repeat(body_len),
    })
    .expect("encode benchmark payload")
}

fn measure<F>(
    operation: &str,
    payload: &str,
    mode: &str,
    outcome: &str,
    iterations: usize,
    samples: usize,
    mut action: F,
) where
    F: FnMut() -> Result<(), String>,
{
    for _ in 0..WARMUP_ITERATIONS {
        action().expect("read-path benchmark warmup");
    }

    let mut sample_ns = Vec::with_capacity(samples);
    for _ in 0..samples {
        let started = Instant::now();
        for _ in 0..iterations {
            action().expect("read-path benchmark iteration");
        }
        sample_ns.push(started.elapsed().as_nanos());
    }
    sample_ns.sort_unstable();
    let median_total_ns = median_u128(&sample_ns);
    let median_ns_per_op = median_total_ns as f64 / iterations as f64;
    let line = format!(
        "{{\"kind\":\"measurement\",\"layer\":\"rust\",\"operation\":\"{operation}\",\"payload\":\"{payload}\",\"mode\":\"{mode}\",\"outcome\":\"{outcome}\",\"iterations\":{iterations},\"samples\":{samples},\"sample_ns\":{},\"median_ns_per_op\":{median_ns_per_op:.3}}}",
        json_u128_array(&sample_ns),
    );
    emit(&line);
}

fn emit_context(iterations: usize, samples: usize) {
    emit(&format!(
        "{{\"kind\":\"context\",\"layer\":\"rust\",\"os\":\"{}\",\"arch\":\"{}\",\"iterations\":{iterations},\"samples\":{samples}}}",
        env::consts::OS,
        env::consts::ARCH,
    ));
}

fn emit(line: &str) {
    println!("DXTR_BOX_READ_PATH_RUST {line}");
    let Some(output) = env::var_os("DXTR_BOX_READ_PATH_RUST_OUTPUT") else {
        return;
    };
    let path = Path::new(&output);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).expect("create Rust benchmark output directory");
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
