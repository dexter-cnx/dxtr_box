use std::fs::{self, File, OpenOptions};
use std::io::{self, Cursor};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use redb::{Database, ReadableTable, TableDefinition};
use rmpv::Value as MessagePackValue;
use serde_json::{json, Map as JsonMap, Value as JsonValue};

use crate::{crypto, db::DATA, inspector::Inspector, DxtrBoxError};

const META: TableDefinition<&str, &[u8]> = TableDefinition::new("meta");
const META_FORMAT_VERSION: &str = "format_version";
const META_ENCRYPTION_MODE: &str = "encryption_mode";
const META_ENCRYPTION_SALT: &str = "encryption_salt";
const META_KEY_CHECK: &str = "key_check";
const FORMAT_VERSION: &[u8] = b"dxtr_box/1";
const ENCRYPTION_NONE: &[u8] = b"none";
const ENCRYPTION_CHACHA20POLY1305: &[u8] = b"chacha20poly1305";
const KEY_CHECK_PLAINTEXT: &[u8] = b"dxtr_box:key-check:v1";

static SNAPSHOT_COUNTER: AtomicU64 = AtomicU64::new(0);

/// A semantically decoded Inspector record rendered as deterministic JSON.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedInspectorRecord {
    pub key: String,
    pub value_json: String,
}

/// Stable failure classes for semantic Inspector decoding.
#[derive(Debug, thiserror::Error)]
pub enum InspectorDecodeError {
    #[error("{0}")]
    Storage(#[from] DxtrBoxError),
    #[error("{0}")]
    Authentication(String),
    #[error("{0}")]
    Decode(String),
    #[error("{0}")]
    Unsupported(String),
}

/// Decode a record from one coherent read-only snapshot.
///
/// `password` is supplied by the caller from a non-argv secret channel such
/// as stdin. The original database file is never opened by redb and is never
/// modified by this operation.
pub fn decode_record(
    inspector: &Inspector,
    box_name: &str,
    key: &str,
    password: Option<&str>,
) -> Result<Option<DecodedInspectorRecord>, InspectorDecodeError> {
    if !inspector.box_exists(box_name)? {
        return Ok(None);
    }

    let source = inspector.base_path().join(format!("{box_name}.dxtr"));
    let snapshot = Snapshot::open(&source)?;
    let encryption = resolve_encryption(snapshot.database(), password)?;

    let read = snapshot
        .database()
        .begin_read()
        .map_err(|error| storage_engine("begin inspector decode read", error))?;
    let table = read
        .open_table(DATA)
        .map_err(|error| storage_engine("open data table", error))?;
    let Some(stored) = table
        .get(key)
        .map_err(|error| storage_engine("read record", error))?
    else {
        return Ok(None);
    };

    let plaintext = encryption.decode(key, stored.value())?;
    let mut cursor = Cursor::new(&plaintext);
    let wire_value = rmpv::decode::read_value(&mut cursor)
        .map_err(|error| InspectorDecodeError::Decode(format!("decode MessagePack: {error}")))?;
    let semantic_value = decode_dxtr_wire_value(wire_value)?;
    let value_json = serde_json::to_string(&semantic_value)
        .map_err(|error| InspectorDecodeError::Decode(format!("render decoded JSON: {error}")))?;

    Ok(Some(DecodedInspectorRecord {
        key: key.to_owned(),
        value_json,
    }))
}

fn decode_dxtr_wire_value(value: MessagePackValue) -> Result<JsonValue, InspectorDecodeError> {
    match value {
        MessagePackValue::Nil => Ok(JsonValue::Null),
        MessagePackValue::Boolean(value) => Ok(JsonValue::Bool(value)),
        MessagePackValue::Integer(value) => {
            if let Some(value) = value.as_i64() {
                Ok(json!(value))
            } else if let Some(value) = value.as_u64() {
                Ok(json!(value))
            } else {
                Err(InspectorDecodeError::Decode(
                    "MessagePack integer is outside JSON integer range".to_owned(),
                ))
            }
        }
        MessagePackValue::F32(value) => Ok(json!(value)),
        MessagePackValue::F64(value) => Ok(json!(value)),
        MessagePackValue::String(value) => value
            .as_str()
            .map(|value| JsonValue::String(value.to_owned()))
            .ok_or_else(|| InspectorDecodeError::Decode("MessagePack string is not UTF-8".to_owned())),
        MessagePackValue::Binary(bytes) => Ok(json!({
            "$dxtrType": "bytes",
            "data": bytes,
        })),
        MessagePackValue::Array(values) => decode_dxtr_array(values),
        MessagePackValue::Map(entries) => decode_dxtr_map(entries),
        MessagePackValue::Ext(_, _) => Err(InspectorDecodeError::Decode(
            "MessagePack extension values are not part of BoxCodec semantics".to_owned(),
        )),
    }
}

fn decode_dxtr_array(values: Vec<MessagePackValue>) -> Result<JsonValue, InspectorDecodeError> {
    if values.len() == 2 {
        if let Some(tag) = values[0].as_str() {
            return match tag {
                "@dxtr:map" => decode_tagged_map(&values[1]),
                "@dxtr:list" => decode_tagged_list(&values[1]),
                "@dxtr:bytes" => decode_tagged_bytes(&values[1]),
                "@dxtr:datetime" => decode_tagged_datetime(&values[1]),
                _ => Ok(JsonValue::Array(
                    values
                        .into_iter()
                        .map(decode_dxtr_wire_value)
                        .collect::<Result<Vec<_>, _>>()?,
                )),
            };
        }
    }

    Ok(JsonValue::Array(
        values
            .into_iter()
            .map(decode_dxtr_wire_value)
            .collect::<Result<Vec<_>, _>>()?,
    ))
}

fn decode_tagged_map(payload: &MessagePackValue) -> Result<JsonValue, InspectorDecodeError> {
    let pairs = payload.as_array().ok_or_else(|| {
        InspectorDecodeError::Decode("invalid @dxtr:map payload".to_owned())
    })?;
    let mut map = JsonMap::new();
    for pair in pairs {
        let pair = pair.as_array().ok_or_else(|| {
            InspectorDecodeError::Decode("invalid @dxtr:map entry".to_owned())
        })?;
        if pair.len() != 2 {
            return Err(InspectorDecodeError::Decode(
                "invalid @dxtr:map entry length".to_owned(),
            ));
        }
        let key = pair[0].as_str().ok_or_else(|| {
            InspectorDecodeError::Decode("dxtr map keys must be strings".to_owned())
        })?;
        map.insert(key.to_owned(), decode_dxtr_wire_value(pair[1].clone())?);
    }
    Ok(JsonValue::Object(map))
}

fn decode_tagged_list(payload: &MessagePackValue) -> Result<JsonValue, InspectorDecodeError> {
    let values = payload.as_array().ok_or_else(|| {
        InspectorDecodeError::Decode("invalid @dxtr:list payload".to_owned())
    })?;
    Ok(JsonValue::Array(
        values
            .iter()
            .cloned()
            .map(decode_dxtr_wire_value)
            .collect::<Result<Vec<_>, _>>()?,
    ))
}

fn decode_tagged_bytes(payload: &MessagePackValue) -> Result<JsonValue, InspectorDecodeError> {
    let bytes = match payload {
        MessagePackValue::Binary(bytes) => bytes.clone(),
        MessagePackValue::Array(values) => values
            .iter()
            .map(|value| {
                value.as_u64().and_then(|value| u8::try_from(value).ok()).ok_or_else(|| {
                    InspectorDecodeError::Decode("invalid @dxtr:bytes payload".to_owned())
                })
            })
            .collect::<Result<Vec<_>, _>>()?,
        _ => {
            return Err(InspectorDecodeError::Decode(
                "invalid @dxtr:bytes payload".to_owned(),
            ))
        }
    };
    Ok(json!({
        "$dxtrType": "bytes",
        "data": bytes,
    }))
}

fn decode_tagged_datetime(payload: &MessagePackValue) -> Result<JsonValue, InspectorDecodeError> {
    let micros = payload.as_i64().ok_or_else(|| {
        InspectorDecodeError::Decode("invalid @dxtr:datetime payload".to_owned())
    })?;
    Ok(json!({
        "$dxtrType": "datetime",
        "microsecondsSinceEpoch": micros,
        "isUtc": true,
    }))
}

fn decode_dxtr_map(
    entries: Vec<(MessagePackValue, MessagePackValue)>,
) -> Result<JsonValue, InspectorDecodeError> {
    let mut map = JsonMap::new();
    for (key, value) in entries {
        let key = key.as_str().ok_or_else(|| {
            InspectorDecodeError::Decode("JSON object keys must be strings".to_owned())
        })?;
        map.insert(key.to_owned(), decode_dxtr_wire_value(value)?);
    }
    Ok(JsonValue::Object(map))
}

#[derive(Debug)]
enum InspectionEncryption {
    Plain,
    Encrypted { key: [u8; 32] },
}

impl InspectionEncryption {
    fn decode(&self, record_key: &str, stored: &[u8]) -> Result<Vec<u8>, InspectorDecodeError> {
        match self {
            Self::Plain => Ok(stored.to_vec()),
            Self::Encrypted { key } => crypto::decrypt_with_aad(key, record_key.as_bytes(), stored)
                .map_err(|_| {
                    InspectorDecodeError::Authentication(
                        "encrypted record authentication failed".to_owned(),
                    )
                }),
        }
    }
}

fn resolve_encryption(
    database: &Database,
    password: Option<&str>,
) -> Result<InspectionEncryption, InspectorDecodeError> {
    let format = read_meta(database, META_FORMAT_VERSION)?;
    if let Some(format) = format.as_deref() {
        if format != FORMAT_VERSION {
            return Err(InspectorDecodeError::Unsupported(
                "unsupported dxtr_box storage format".to_owned(),
            ));
        }
    }

    let mode = match format {
        None => ENCRYPTION_NONE.to_vec(),
        Some(_) => read_meta(database, META_ENCRYPTION_MODE)?.ok_or_else(|| {
            InspectorDecodeError::Decode("box metadata is missing encryption mode".to_owned())
        })?,
    };

    if mode == ENCRYPTION_NONE {
        if password.is_some() {
            return Err(InspectorDecodeError::Authentication(
                "box is not encrypted; omit --key-stdin".to_owned(),
            ));
        }
        return Ok(InspectionEncryption::Plain);
    }

    if mode != ENCRYPTION_CHACHA20POLY1305 {
        return Err(InspectorDecodeError::Unsupported(
            "unsupported box encryption mode".to_owned(),
        ));
    }

    let password = password.ok_or_else(|| {
        InspectorDecodeError::Authentication(
            "encrypted box requires key material from --key-stdin".to_owned(),
        )
    })?;
    if password.is_empty() {
        return Err(InspectorDecodeError::Authentication(
            "encryption key cannot be empty".to_owned(),
        ));
    }

    let salt_bytes = read_meta(database, META_ENCRYPTION_SALT)?.ok_or_else(|| {
        InspectorDecodeError::Decode("encrypted box metadata is missing salt".to_owned())
    })?;
    let salt: [u8; crypto::SALT_LEN] = salt_bytes.try_into().map_err(|_| {
        InspectorDecodeError::Decode("encrypted box metadata has invalid salt length".to_owned())
    })?;
    let key_check = read_meta(database, META_KEY_CHECK)?.ok_or_else(|| {
        InspectorDecodeError::Decode("encrypted box metadata is missing key check".to_owned())
    })?;
    let key = crypto::derive_key(password, &salt).map_err(|error| {
        InspectorDecodeError::Authentication(format!("derive encryption key: {error}"))
    })?;
    let plaintext = crypto::decrypt(&key, &key_check)
        .map_err(|_| InspectorDecodeError::Authentication("invalid encryption key".to_owned()))?;
    if plaintext != KEY_CHECK_PLAINTEXT {
        return Err(InspectorDecodeError::Authentication(
            "invalid encryption key".to_owned(),
        ));
    }

    Ok(InspectionEncryption::Encrypted { key })
}

fn read_meta(database: &Database, key: &str) -> Result<Option<Vec<u8>>, InspectorDecodeError> {
    let read = database
        .begin_read()
        .map_err(|error| storage_engine("begin metadata read", error))?;
    let table = match read.open_table(META) {
        Ok(table) => table,
        Err(redb::TableError::TableDoesNotExist(_)) => return Ok(None),
        Err(error) => return Err(storage_engine("open metadata table", error)),
    };
    table
        .get(key)
        .map_err(|error| storage_engine("read metadata", error))
        .map(|value| value.map(|value| value.value().to_vec()))
}

fn storage_engine(context: &str, error: impl std::fmt::Display) -> InspectorDecodeError {
    InspectorDecodeError::Storage(DxtrBoxError::engine(format!("{context}: {error}")))
}

struct Snapshot {
    database: Option<Database>,
    path: PathBuf,
}

impl Snapshot {
    fn open(source: &Path) -> Result<Self, InspectorDecodeError> {
        let path = create_snapshot_copy(source)?;
        match Database::open(&path) {
            Ok(database) => Ok(Self {
                database: Some(database),
                path,
            }),
            Err(error) => {
                let _ = fs::remove_file(&path);
                Err(InspectorDecodeError::Storage(DxtrBoxError::invalid_input(
                    format!("open box {source:?} inspection snapshot: {error}"),
                )))
            }
        }
    }

    fn database(&self) -> &Database {
        self.database.as_ref().expect("snapshot database is open")
    }
}

impl Drop for Snapshot {
    fn drop(&mut self) {
        self.database.take();
        let _ = fs::remove_file(&self.path);
    }
}

fn create_snapshot_copy(source: &Path) -> Result<PathBuf, InspectorDecodeError> {
    let mut source_file = File::open(source).map_err(|error| {
        InspectorDecodeError::Storage(DxtrBoxError::invalid_input(format!(
            "open box {source:?} for inspection: {error}"
        )))
    })?;

    for _ in 0..16 {
        let nonce = SNAPSHOT_COUNTER.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "dxtr-box-inspect-decode-{}-{nonce}.dxtr",
            std::process::id()
        ));
        match OpenOptions::new().write(true).create_new(true).open(&path) {
            Ok(mut snapshot_file) => {
                if let Err(error) = io::copy(&mut source_file, &mut snapshot_file) {
                    let _ = fs::remove_file(&path);
                    return Err(storage_engine("copy inspection snapshot", error));
                }
                return Ok(path);
            }
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => return Err(storage_engine("create inspection snapshot", error)),
        }
    }

    Err(InspectorDecodeError::Storage(DxtrBoxError::engine(
        "could not allocate a unique inspector decode snapshot",
    )))
}

#[cfg(test)]
mod tests {
    use std::fs;

    use redb::Database;
    use serde_json::json;
    use tempfile::tempdir;

    use super::*;

    fn create_plain_box(path: &Path, key: &str, value: &[u8]) {
        let database = Database::create(path).expect("create database");
        let write = database.begin_write().expect("begin write");
        {
            let mut data = write.open_table(DATA).expect("open data");
            data.insert(key, value).expect("insert value");
            let mut meta = write.open_table(META).expect("open meta");
            meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                .expect("format version");
            meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_NONE)
                .expect("encryption mode");
        }
        write.commit().expect("commit");
    }

    #[test]
    fn decodes_plaintext_messagepack_without_changing_source_bytes() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("records.dxtr");
        let payload = rmp_serde::to_vec(&json!({"z": 1, "a": true})).expect("encode");
        create_plain_box(&path, "alpha", &payload);
        let before = fs::read(&path).expect("read before");

        let inspector = Inspector::open(root.path()).expect("inspector");
        let record = decode_record(&inspector, "records", "alpha", None)
            .expect("decode")
            .expect("record");

        assert_eq!(record.value_json, "{\"a\":true,\"z\":1}");
        assert_eq!(fs::read(&path).expect("read after"), before);
    }

    #[test]
    fn decodes_box_codec_tags_into_semantic_json() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("tagged.dxtr");
        let wire = MessagePackValue::Array(vec![
            MessagePackValue::from("@dxtr:map"),
            MessagePackValue::Array(vec![
                MessagePackValue::Array(vec![
                    MessagePackValue::from("id"),
                    MessagePackValue::from(7),
                ]),
                MessagePackValue::Array(vec![
                    MessagePackValue::from("items"),
                    MessagePackValue::Array(vec![
                        MessagePackValue::from("@dxtr:list"),
                        MessagePackValue::Array(vec![MessagePackValue::from(true)]),
                    ]),
                ]),
                MessagePackValue::Array(vec![
                    MessagePackValue::from("bytes"),
                    MessagePackValue::Array(vec![
                        MessagePackValue::from("@dxtr:bytes"),
                        MessagePackValue::Binary(vec![1, 2, 3]),
                    ]),
                ]),
                MessagePackValue::Array(vec![
                    MessagePackValue::from("when"),
                    MessagePackValue::Array(vec![
                        MessagePackValue::from("@dxtr:datetime"),
                        MessagePackValue::from(123456_i64),
                    ]),
                ]),
            ]),
        ]);
        let mut payload = Vec::new();
        rmpv::encode::write_value(&mut payload, &wire).expect("encode tagged payload");
        create_plain_box(&path, "alpha", &payload);

        let inspector = Inspector::open(root.path()).expect("inspector");
        let record = decode_record(&inspector, "tagged", "alpha", None)
            .expect("decode")
            .expect("record");

        assert_eq!(
            record.value_json,
            "{\"bytes\":{\"$dxtrType\":\"bytes\",\"data\":[1,2,3]},\"id\":7,\"items\":[true],\"when\":{\"$dxtrType\":\"datetime\",\"isUtc\":true,\"microsecondsSinceEpoch\":123456}}"
        );
    }

    #[test]
    fn encrypted_decode_requires_valid_key_and_preserves_source_bytes() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("secure.dxtr");
        let database = Database::create(&path).expect("create database");
        let salt = crypto::new_salt();
        let key = crypto::derive_key("secret", &salt).expect("derive key");
        let key_check = crypto::encrypt(&key, KEY_CHECK_PLAINTEXT).expect("key check");
        let payload = rmp_serde::to_vec(&json!({"secure": true})).expect("encode");
        let encrypted = crypto::encrypt_with_aad(&key, b"alpha", &payload).expect("encrypt");
        let write = database.begin_write().expect("begin write");
        {
            let mut data = write.open_table(DATA).expect("open data");
            data.insert("alpha", encrypted.as_slice()).expect("insert");
            let mut meta = write.open_table(META).expect("open meta");
            meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                .expect("format version");
            meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_CHACHA20POLY1305)
                .expect("mode");
            meta.insert(META_ENCRYPTION_SALT, salt.as_slice())
                .expect("salt");
            meta.insert(META_KEY_CHECK, key_check.as_slice())
                .expect("key check");
        }
        write.commit().expect("commit");
        drop(database);
        let before = fs::read(&path).expect("read before");

        let inspector = Inspector::open(root.path()).expect("inspector");
        assert!(matches!(
            decode_record(&inspector, "secure", "alpha", Some("wrong")),
            Err(InspectorDecodeError::Authentication(_))
        ));
        let record = decode_record(&inspector, "secure", "alpha", Some("secret"))
            .expect("decode")
            .expect("record");
        assert_eq!(record.value_json, "{\"secure\":true}");
        assert_eq!(fs::read(&path).expect("read after"), before);
    }

    #[test]
    fn encrypted_decode_accepts_key_with_trailing_newline() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("secure.dxtr");
        let database = Database::create(&path).expect("create database");
        let salt = crypto::new_salt();
        let key = crypto::derive_key("secret\n", &salt).expect("derive key");
        let key_check = crypto::encrypt(&key, KEY_CHECK_PLAINTEXT).expect("key check");
        let payload = rmp_serde::to_vec(&json!({"secure": true})).expect("encode");
        let encrypted = crypto::encrypt_with_aad(&key, b"alpha", &payload).expect("encrypt");
        let write = database.begin_write().expect("begin write");
        {
            let mut data = write.open_table(DATA).expect("open data");
            data.insert("alpha", encrypted.as_slice()).expect("insert");
            let mut meta = write.open_table(META).expect("open meta");
            meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                .expect("format version");
            meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_CHACHA20POLY1305)
                .expect("mode");
            meta.insert(META_ENCRYPTION_SALT, salt.as_slice())
                .expect("salt");
            meta.insert(META_KEY_CHECK, key_check.as_slice())
                .expect("key check");
        }
        write.commit().expect("commit");
        drop(database);

        let inspector = Inspector::open(root.path()).expect("inspector");
        assert!(decode_record(&inspector, "secure", "alpha", Some("secret\n"))
            .expect("decode")
            .is_some());
    }

    #[test]
    fn malformed_messagepack_is_a_decode_failure() {
        let root = tempdir().expect("tempdir");
        let path = root.path().join("broken.dxtr");
        create_plain_box(&path, "bad", &[0xc1]);

        let inspector = Inspector::open(root.path()).expect("inspector");
        assert!(matches!(
            decode_record(&inspector, "broken", "bad", None),
            Err(InspectorDecodeError::Decode(_))
        ));
    }
}
