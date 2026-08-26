use std::fs;
use std::path::{Path, PathBuf};

use crate::DxtrBoxError;

/// Read-only inspection entry point for an existing Dxtr_Box base directory.
///
/// Unlike the runtime `db::init` path, this constructor never creates the
/// directory and never changes process-global runtime state.
#[derive(Debug, Clone)]
pub struct Inspector {
    base_path: PathBuf,
}

impl Inspector {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, DxtrBoxError> {
        let requested = path.as_ref();
        let metadata = fs::metadata(requested).map_err(|error| {
            DxtrBoxError::invalid_input(format!(
                "inspector path {:?} is not accessible: {error}",
                requested
            ))
        })?;
        if !metadata.is_dir() {
            return Err(DxtrBoxError::invalid_input(format!(
                "inspector path {:?} is not a directory",
                requested
            )));
        }

        let base_path = fs::canonicalize(requested).map_err(|error| {
            DxtrBoxError::invalid_input(format!("resolve inspector path {:?}: {error}", requested))
        })?;
        fs::read_dir(&base_path).map_err(|error| {
            DxtrBoxError::invalid_input(format!(
                "inspector path {:?} is not readable: {error}",
                base_path
            ))
        })?;
        Ok(Self { base_path })
    }

    pub fn base_path(&self) -> &Path {
        &self.base_path
    }

    /// Lists box names represented by `.dxtr` files in deterministic order.
    ///
    /// This operation intentionally does not open database files. Commands
    /// that need database contents must use a separately tested non-mutating
    /// inspection seam rather than the runtime `db::open` path.
    pub fn boxes(&self) -> Result<Vec<String>, DxtrBoxError> {
        let entries = fs::read_dir(&self.base_path).map_err(|error| {
            DxtrBoxError::invalid_input(format!(
                "inspector path {:?} is not readable: {error}",
                self.base_path
            ))
        })?;

        let mut boxes = Vec::new();
        for entry in entries {
            let entry = entry.map_err(|error| {
                DxtrBoxError::invalid_input(format!("read inspector directory entry: {error}"))
            })?;
            let file_type = entry.file_type().map_err(|error| {
                DxtrBoxError::invalid_input(format!("read inspector file type: {error}"))
            })?;
            if !file_type.is_file() {
                continue;
            }

            let path = entry.path();
            if path.extension().and_then(|extension| extension.to_str()) != Some("dxtr") {
                continue;
            }
            if let Some(name) = path.file_stem().and_then(|name| name.to_str()) {
                boxes.push(name.to_owned());
            }
        }

        boxes.sort_unstable();
        Ok(boxes)
    }
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::tempdir;

    use super::Inspector;

    #[test]
    fn open_rejects_missing_path_without_creating_it() {
        let root = tempdir().expect("tempdir");
        let missing = root.path().join("missing");

        assert!(Inspector::open(&missing).is_err());
        assert!(!missing.exists());
    }

    #[test]
    fn boxes_are_sorted_and_listing_is_byte_for_byte_read_only() {
        let root = tempdir().expect("tempdir");
        let alpha = root.path().join("alpha.dxtr");
        let zebra = root.path().join("zebra.dxtr");
        fs::write(&zebra, b"zebra sentinel").expect("write zebra");
        fs::write(&alpha, b"alpha sentinel").expect("write alpha");
        fs::write(root.path().join("ignore.txt"), b"ignore").expect("write ignore");

        let before_alpha = fs::read(&alpha).expect("read alpha before");
        let before_zebra = fs::read(&zebra).expect("read zebra before");

        let inspector = Inspector::open(root.path()).expect("open inspector");
        assert_eq!(
            inspector.boxes().expect("list boxes"),
            vec!["alpha", "zebra"]
        );

        assert_eq!(fs::read(&alpha).expect("read alpha after"), before_alpha);
        assert_eq!(fs::read(&zebra).expect("read zebra after"), before_zebra);
    }
}
