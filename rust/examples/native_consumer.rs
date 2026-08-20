use std::{env, fs, path::PathBuf};

use rust_lib_dxtr_box::DxtrBox;
#[cfg(feature = "full")]
use rust_lib_dxtr_box::SortOrder;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = example_root();
    fs::create_dir_all(&root)?;

    let db = DxtrBox::open(&root)?;
    let assets = db.box_("assets")?;

    #[cfg(feature = "full")]
    {
        assets.put("first", asset("active", 10))?;
        assets.put("second", asset("active", 20))?;
        assets.put("archived", asset("archived", 30))?;
        assets.create_index("by_status", "status")?;

        let rows = assets
            .query()
            .where_("status")
            .equals("active")
            .order_by("captured_at", SortOrder::Descending)
            .limit(200)
            .find()?;
        println!("active rows: {}", rows.len());
    }

    #[cfg(not(feature = "full"))]
    {
        assets.put("first", vec![1])?;
        assets.put("second", vec![2])?;
        println!("assets: {}", assets.len()?);
    }

    assets.close()?;
    Ok(())
}

fn example_root() -> PathBuf {
    env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| env::temp_dir().join("dxtr-box-rust-native-example"))
}

#[cfg(feature = "full")]
fn asset(status: &str, captured_at: i64) -> Vec<u8> {
    use rmpv::Value;

    let value = Value::Array(vec![
        Value::from("@dxtr:map"),
        Value::Array(vec![
            Value::Array(vec![Value::from("status"), Value::from(status)]),
            Value::Array(vec![Value::from("captured_at"), Value::from(captured_at)]),
        ]),
    ]);
    let mut bytes = Vec::new();
    rmpv::encode::write_value(&mut bytes, &value).expect("encode example value");
    bytes
}
