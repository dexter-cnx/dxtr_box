use std::collections::HashMap;

use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use parking_lot::RwLock;

#[cfg(feature = "full")]
use crate::query;
use crate::{core, frb_generated::StreamSink};

#[derive(Clone)]
pub enum NativeBoxEventType {
    Put,
    Delete,
    Clear,
}

#[derive(Clone)]
pub struct NativeBoxEvent {
    pub box_name: String,
    pub event_type: NativeBoxEventType,
    pub key: Option<String>,
    pub value: Option<Vec<u8>>,
}

pub struct NativeQueryRecord {
    pub key: String,
    pub value: Vec<u8>,
}

pub struct NativeBatchRecord {
    pub key: String,
    pub value: Vec<u8>,
}

pub struct NativeIndexDefinition {
    pub name: String,
    pub field: String,
}

impl From<core::BoxEvent> for NativeBoxEvent {
    fn from(event: core::BoxEvent) -> Self {
        Self {
            box_name: event.box_name,
            event_type: match event.event_type {
                core::BoxEventType::Put => NativeBoxEventType::Put,
                core::BoxEventType::Delete => NativeBoxEventType::Delete,
                core::BoxEventType::Clear => NativeBoxEventType::Clear,
            },
            key: event.key,
            value: event.value,
        }
    }
}

impl From<core::QueryRecord> for NativeQueryRecord {
    fn from(record: core::QueryRecord) -> Self {
        Self {
            key: record.key,
            value: record.value,
        }
    }
}

impl From<core::BatchRecord> for NativeBatchRecord {
    fn from(record: core::BatchRecord) -> Self {
        Self {
            key: record.key,
            value: record.value,
        }
    }
}

impl From<core::IndexDefinition> for NativeIndexDefinition {
    fn from(definition: core::IndexDefinition) -> Self {
        Self {
            name: definition.name,
            field: definition.field,
        }
    }
}

type Watchers = HashMap<String, HashMap<String, StreamSink<NativeBoxEvent>>>;

static WATCHERS: Lazy<RwLock<Watchers>> = Lazy::new(|| RwLock::new(HashMap::new()));

fn emit_event(event: NativeBoxEvent) {
    let subscribers = WATCHERS
        .read()
        .get(&event.box_name)
        .map(|watchers| {
            watchers
                .iter()
                .map(|(id, sink)| (id.clone(), sink.clone()))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    let failed = subscribers
        .into_iter()
        .filter_map(|(id, sink)| sink.add(event.clone()).err().map(|_| id))
        .collect::<Vec<_>>();

    if failed.is_empty() {
        return;
    }

    let mut all_watchers = WATCHERS.write();
    let remove_box = if let Some(watchers) = all_watchers.get_mut(&event.box_name) {
        for id in failed {
            watchers.remove(&id);
        }
        watchers.is_empty()
    } else {
        false
    };
    if remove_box {
        all_watchers.remove(&event.box_name);
    }
}

#[frb(sync)]
pub fn init_db(path: String) -> Result<(), String> {
    core::init(std::path::Path::new(&path))
}

#[frb(sync)]
pub fn open_box(name: String, encryption_key: Option<String>) -> Result<(), String> {
    core::open_box(&name, encryption_key.as_deref())
}

#[frb(sync)]
pub fn close_box(name: String) -> Result<(), String> {
    core::close_box(&name)
}

#[frb(sync)]
pub fn delete_box(name: String) -> Result<(), String> {
    core::delete_box_with(&name, || {
        WATCHERS.write().remove(&name);
    })
}

#[frb(sync)]
pub fn encrypt_box(name: String, encryption_key: String) -> Result<(), String> {
    core::encrypt_box(&name, &encryption_key)
}

#[frb(sync)]
pub fn box_exists(name: String) -> Result<bool, String> {
    core::box_exists(&name)
}

#[frb(stream_dart_await)]
pub fn watch_box(
    box_name: String,
    watcher_id: String,
    sink: StreamSink<NativeBoxEvent>,
) -> Result<(), String> {
    if watcher_id.is_empty() {
        return Err("watcher id cannot be empty".to_string());
    }

    core::with_box_mutation_lock(&box_name, || {
        core::len(&box_name)?;
        WATCHERS
            .write()
            .entry(box_name.clone())
            .or_default()
            .insert(watcher_id, sink);
        Ok(())
    })
}

#[frb(sync)]
pub fn unwatch_box(box_name: String, watcher_id: String) -> Result<(), String> {
    core::with_box_mutation_lock(&box_name, || {
        let mut all_watchers = WATCHERS.write();
        let remove_box = if let Some(watchers) = all_watchers.get_mut(&box_name) {
            watchers.remove(&watcher_id);
            watchers.is_empty()
        } else {
            false
        };
        if remove_box {
            all_watchers.remove(&box_name);
        }
        Ok(())
    })
}

pub fn put(box_name: String, key: String, value: Vec<u8>) -> Result<(), String> {
    core::put_with(&box_name, key, value, |event| emit_event(event.into()))
}

pub fn put_all(box_name: String, entries: Vec<(String, Vec<u8>)>) -> Result<(), String> {
    core::put_all_with(&box_name, entries, |event| emit_event(event.into()))
}

#[frb(sync)]
pub fn get(box_name: String, key: String) -> Result<Option<Vec<u8>>, String> {
    core::get(&box_name, &key)
}

#[frb(sync)]
pub fn contains_key(box_name: String, key: String) -> Result<bool, String> {
    core::contains_key(&box_name, &key)
}

pub fn get_all(box_name: String, keys: Vec<String>) -> Result<Vec<NativeBatchRecord>, String> {
    core::get_all(&box_name, &keys).map(|records| records.into_iter().map(Into::into).collect())
}

pub fn delete(box_name: String, key: String) -> Result<(), String> {
    core::delete_with(&box_name, key, |event| emit_event(event.into()))
}

pub fn delete_all(box_name: String, keys: Vec<String>) -> Result<Vec<String>, String> {
    core::delete_all_with(&box_name, &keys, |event| emit_event(event.into()))
}

pub fn clear(box_name: String) -> Result<(), String> {
    core::clear_with(&box_name, |event| emit_event(event.into()))
}

pub fn compact(box_name: String) -> Result<bool, String> {
    core::compact(&box_name)
}

pub fn scan_query(
    box_name: String,
    query_payload: Vec<u8>,
) -> Result<Vec<NativeQueryRecord>, String> {
    #[cfg(feature = "full")]
    {
        let spec = query::decode_query(&query_payload)?;
        core::query(&box_name, &spec).map(|records| records.into_iter().map(Into::into).collect())
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (box_name, query_payload);
        Err("native query execution requires the full profile".to_string())
    }
}

pub fn create_index(box_name: String, name: String, field: String) -> Result<(), String> {
    core::create_index(&box_name, &name, &field)
}

pub fn list_indexes(box_name: String) -> Result<Vec<NativeIndexDefinition>, String> {
    core::list_indexes(&box_name)
        .map(|definitions| definitions.into_iter().map(Into::into).collect())
}

pub fn drop_index(box_name: String, name: String) -> Result<bool, String> {
    core::drop_index(&box_name, &name)
}

pub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {
    core::all_keys(&box_name)
}

pub fn length(box_name: String) -> Result<u64, String> {
    core::len(&box_name)
}
