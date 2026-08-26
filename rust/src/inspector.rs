use std::fs::{self, File, OpenOptions};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use redb::{Database, ReadableTable, TableDefinition};

use crate::{db::DATA, DxtrBoxError};

#[cfg(feature = "full")]
const INDEX_DEFINITIONS: TableDefinition<&str, &str> = TableDefinition::new("index_definitions");

/// Maximum number of keys returned by one bounded inspector request.
pub const MAX_KEY_PAGE_SIZE: usize = 1000;

static SNAPSHOT_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Raw record returned by the read-only inspector.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InspectorRecord {
    pub key: String,
    pub value: Vec<u8>,
}

/// Persisted index metadata returned by the read-only inspector.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InspectorIndex {
    pub name: String,
    pub field: String,
}

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

    /// Returns whether the named box exists in this inspector directory.
    pub fn box_exists(&self, box_name: &str) -> Result<bool, DxtrBoxError> {
        Ok(self.boxes()?.iter().any(|name| name == box_name))
    }

    /// Returns a deterministic bounded page of record keys.
    pub fn keys(
        &self,
        box_name: &str,
        offset: usize,
        limit: usize,
    ) -> Result<Vec<String>, DxtrBoxError> {
        if limit == 0 || limit > MAX_KEY_PAGE_SIZE {
            return Err(DxtrBoxError::invalid_input(format!(
                "limit must be between 1 and {MAX_KEY_PAGE_SIZE}"
            )));
        }

        let snapshot = self.open_box_snapshot(box_name)?;
        let read = snapshot
            .database()
            .begin_read()
            .map_err(|error| DxtrBoxError::engine(format!("begin inspector read: {error}")))?;
        let table = read
            .open_table(DATA)
            .map_err(|error| DxtrBoxError::engine(format!("open data table: {error}")))?;
        table
            .iter()
            .map_err(|error| DxtrBoxError::engine(format!("iterate data table: {error}")))?
            .skip(offset)
            .take(limit)
            .map(|item| {
                item.map(|(key, _)| key.value().to_owned())
                    .map_err(|error| DxtrBoxError::engine(format!("read record key: {error}")))
            })
            .collect()
    }

    /// Reads one raw persisted record without mutating the database.
    pub fn get(&self, box_name: &str, key: &str) -> Result<Option<InspectorRecord>, DxtrBoxError> {
        let snapshot = self.open_box_snapshot(box_name)?;
        let read = snapshot
            .database()
            .begin_read()
            .map_err(|error| DxtrBoxError::engine(format!("begin inspector read: {error}")))?;
        let table = read
            .open_table(DATA)
            .map_err(|error| DxtrBoxError::engine(format!("open data table: {error}")))?;
        let value = table
            .get(key)
            .map_err(|error| DxtrBoxError::engine(format!("read record: {error}")))?;
        Ok(value.map(|value| InspectorRecord {
            key: key.to_owned(),
            value: value.value().to_vec(),
        }))
    }

    /// Lists persisted index definitions in deterministic name order.
    #[cfg(feature = "full")]
    pub fn indexes(&self, box_name: &str) -> Result<Vec<InspectorIndex>, DxtrBoxError> {
        let snapshot = self.open_box_snapshot(box_name)?;
        let read = snapshot
            .database()
            .begin_read()
            .map_err(|error| DxtrBoxError::engine(format!("begin inspector read: {error}")))?;
        let table = match read.open_table(INDEX_DEFINITIONS) {
            Ok(table) => table,
            Err(redb::TableError::TableDoesNotExist(_)) => return Ok(Vec::new()),
            Err(error) => {
                return Err(DxtrBoxError::engine(format!(
                    "open index definitions table: {error}"
                )))
            }
        };
        let mut indexes = table
            .iter()
            .map_err(|error| DxtrBoxError::engine(format!("iterate index definitions: {error}")))?
            .map(|item| {
                item.map(|(name, field)| InspectorIndex {
                    name: name.value().to_owned(),
                    field: field.value().to_owned(),
                })
                .map_err(|error| DxtrBoxError::engine(format!("read index definition: {error}")))
            })
            .collect::<Result<Vec<_>, _>>()?;
        indexes.sort_unstable_by(|left, right| left.name.cmp(&right.name));
        Ok(indexes)
    }

    /// Reports the full-profile requirement without opening the database.
    #[cfg(not(feature = "full"))]
    pub fn indexes(&self, _box_name: &str) -> Result<Vec<InspectorIndex>, DxtrBoxError> {
        Err(DxtrBoxError::unsupported(
            "full",
            "persisted index inspection requires the full native profile",
        ))
    }

    fn open_box_snapshot(&self, box_name: &str) -> Result<InspectorSnapshot, DxtrBoxError> {
        if !self.box_exists(box_name)? {
            return Err(DxtrBoxError::invalid_input(format!(
                "box '{box_name}' was not found"
            )));
        }

        let source = self.base_path.join(format!("{box_name}.dxtr"));
        let snapshot_path = create_snapshot_copy(&source)?;
        match Database::open(&snapshot_path) {
            Ok(database) => Ok(InspectorSnapshot {
                database: Some(database),
                path: snapshot_path,
            }),
            Err(error) => {
                let _ = fs::remove_file(&snapshot_path);
                Err(DxtrBoxError::invalid_input(format!(
                    "open box {:?} inspection snapshot: {error}",
                    source
                )))
            }
        }
    }
}

struct InspectorSnapshot {
    database: Option<Database>,
    path: PathBuf,
}

impl InspectorSnapshot {
    fn database(&self) -> &Database {
        self.database.as_ref().expect("snapshot database is open")
    }
}

impl Drop for InspectorSnapshot {
    fn drop(&mut self) {
        self.database.take();
        let _ = fs::remove_file(&self.path);
    }
}

fn create_snapshot_copy(source: &Path) -> Result<PathBuf, DxtrBoxError> {
    let mut source_file = File::open(source).map_err(|error| {
        DxtrBoxError::invalid_input(format!("open box {:?} for inspection: {error}", source))
    })?;

    for _ in 0..16 {
        let nonce = SNAPSHOT_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "dxtr-box-inspect-{}-{nonce}.dxtr",
            std::process::id()
        ));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(mut snapshot_file) => {
                if let Err(error) = io::copy(&mut source_file, &mut snapshot_file) {
                    let _ = fs::remove_file(&path);
                    return Err(DxtrBoxError::engine(format!(
                        "copy box {:?} into inspection snapshot: {error}",
                        source
                    )));
                }
                return Ok(path);
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(DxtrBoxError::engine(format!(
                    "create inspection snapshot: {error}"
                )))
            }
        }
    }

    Err(DxtrBoxError::engine(
        "could not allocate a unique inspection snapshot",
    ))
}

#[cfg(test)]
mod tests {
    use std::fs;

    use redb::Database;
    use tempfile::tempdir;

    use super::Inspector;
    use crate::db::DATA;

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

    #[test]
    fn keys_and_get_use_snapshot_without_changing_source_bytes() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("records.dxtr");
        let db = Database::create(&path).expect("create database");
        let write = db.begin_write().expect("begin write");
        {
            let mut table = write.open_table(DATA).expect("open data");
            table
                .insert("alpha", b"one".as_slice())
                .expect("insert alpha");
            table
                .insert("zebra", b"two".as_slice())
                .expect("insert zebra");
        }
        write.commit().expect("commit");
        drop(db);

        let before = fs::read(&path).expect("read before");
        let inspector = Inspector::open(root.path()).expect("open inspector");
        assert_eq!(
            inspector.keys("records", 0, 1).expect("keys"),
            vec!["alpha"]
        );
        let record = inspector
            .get("records", "zebra")
            .expect("get")
            .expect("record");
        assert_eq!(record.value, b"two");
        assert_eq!(fs::read(&path).expect("read after"), before);
    }

    #[cfg(feature = "full")]
    #[test]
    fn indexes_are_empty_when_index_table_has_not_been_created() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("records.dxtr");
        let db = Database::create(&path).expect("create database");
        let write = db.begin_write().expect("begin write");
        {
            write.open_table(DATA).expect("open data");
        }
        write.commit().expect("commit");
        drop(db);

        let inspector = Inspector::open(root.path()).expect("open inspector");
        assert!(inspector.indexes("records").expect("indexes").is_empty());
    }
}
