#[cfg(feature = "full")]
use std::{env, fs, path::PathBuf, time::Instant};

#[cfg(feature = "full")]
use rust_lib_dxtr_box::DxtrBox;

#[cfg(feature = "full")]
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = benchmark_root();
    if root.exists() {
        fs::remove_dir_all(&root)?;
    }
    fs::create_dir_all(&root)?;

    let iterations = env_usize("DXTR_BOX_STARTUP_ITERATIONS", 100);
    if iterations == 0 {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            "DXTR_BOX_STARTUP_ITERATIONS must be greater than zero",
        )
        .into());
    }

    let record_counts = [0usize, 1_000, 10_000];
    let index_counts = [0usize, 1, 4];

    let db = DxtrBox::open(&root)?;
    for records in record_counts {
        for indexes in index_counts {
            let name = format!("startup_r{records}_i{indexes}");
            prepare_fixture(&db, &name, records, indexes)?;
            benchmark_case(&db, &name, records, indexes, iterations)?;
        }
    }

    Ok(())
}

#[cfg(not(feature = "full"))]
fn main() {
    eprintln!("startup_benchmark requires the full native profile");
    std::process::exit(2);
}

#[cfg(feature = "full")]
fn prepare_fixture(
    db: &DxtrBox,
    name: &str,
    records: usize,
    indexes: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    let box_ = db.box_(name)?;
    if records > 0 {
        let entries = (0..records)
            .map(|i| (format!("key-{i:08}"), record(i)))
            .collect::<Vec<_>>();
        box_.put_all(entries)?;
    }
    for index in 0..indexes {
        box_.create_index(&format!("idx_{index}"), &format!("field_{index}"))?;
    }
    box_.close()?;
    Ok(())
}

#[cfg(feature = "full")]
fn benchmark_case(
    db: &DxtrBox,
    name: &str,
    records: usize,
    indexes: usize,
    iterations: usize,
) -> Result<(), Box<dyn std::error::Error>> {
    let first_started = Instant::now();
    let first = db.box_(name)?;
    let first_open_us = first_started.elapsed().as_secs_f64() * 1_000_000.0;
    first.close()?;

    let mut reopen_us = Vec::with_capacity(iterations);
    for _ in 0..iterations {
        let started = Instant::now();
        let handle = db.box_(name)?;
        reopen_us.push(started.elapsed().as_secs_f64() * 1_000_000.0);
        handle.close()?;
    }
    reopen_us.sort_by(f64::total_cmp);

    println!(
        "{{\"records\":{records},\"indexes\":{indexes},\"iterations\":{iterations},\"first_open_us\":{first_open_us:.3},\"reopen_p50_us\":{:.3},\"reopen_p95_us\":{:.3},\"reopen_max_us\":{:.3}}}",
        percentile(&reopen_us, 0.50),
        percentile(&reopen_us, 0.95),
        reopen_us.last().copied().unwrap_or(0.0),
    );
    Ok(())
}

#[cfg(feature = "full")]
fn percentile(values: &[f64], quantile: f64) -> f64 {
    if values.is_empty() {
        return 0.0;
    }
    let position = ((values.len() - 1) as f64 * quantile).round() as usize;
    values[position]
}

#[cfg(feature = "full")]
fn record(seed: usize) -> Vec<u8> {
    use rmpv::Value;

    let mut fields = Vec::with_capacity(4);
    for index in 0..4 {
        fields.push(Value::Array(vec![
            Value::from(format!("field_{index}")),
            Value::from((seed % 100) as i64),
        ]));
    }
    let value = Value::Array(vec![Value::from("@dxtr:map"), Value::Array(fields)]);
    let mut bytes = Vec::new();
    rmpv::encode::write_value(&mut bytes, &value).expect("encode benchmark value");
    bytes
}

#[cfg(feature = "full")]
fn benchmark_root() -> PathBuf {
    env::var_os("DXTR_BOX_STARTUP_ROOT")
        .map(PathBuf::from)
        .unwrap_or_else(env::temp_dir)
        .join("dxtr-box-startup-benchmark")
}

#[cfg(feature = "full")]
fn env_usize(name: &str, default: usize) -> usize {
    env::var(name)
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(default)
}
