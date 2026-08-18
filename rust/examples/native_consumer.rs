use std::{env, fs, path::PathBuf};

use rust_lib_dxtr_box::DxtrBox;
#[cfg(feature = "full")]
use rust_lib_dxtr_box::SortOrder;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = example_root();
    fs::create_dir_all(&root)?;

    let db = DxtrBox::open(&root)?;
    let assets = db.box_("assets")?;

    assets.put("first", vec![1])?;
    assets.put("second", vec![2])?;
    println!("assets: {}", assets.len()?);

    #[cfg(feature = "full")]
    {
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

    assets.close()?;
    Ok(())
}

fn example_root() -> PathBuf {
    env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| env::temp_dir().join("dxtr-box-rust-native-example"))
}
