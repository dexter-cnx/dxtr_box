use std::{collections::HashMap, sync::Arc};

use flutter_rust_bridge::frb;
use once_cell::sync::Lazy;
use parking_lot::{Mutex, RwLock};

use crate::{db, frb_generated::StreamSink};
#[cfg(feature = "full")]
use crate::{index, query};

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

pub struct NativeIndexDefinition {
    pub name: String,
    pub field: String,
}

type Watchers = HashMap<String, HashMap<String, StreamSink<NativeBoxEvent>>>;
type MutationLocks = HashMap<String, Arc<Mutex<()>>>;

static WATCHERS: Lazy<RwLock<Watchers>> = Lazy::new(|| RwLock::new(HashMap::new()));
static MUTATION_LOCKS: Lazy<RwLock<MutationLocks>> = Lazy::new(|| RwLock::new(HashMap::new()));

fn mutation_lock(box_name: &str) -> Arc<Mutex<()>> {
    if let Some(lock) = MUTATION_LOCKS.read().get(box_name).cloned() {
        return lock;
    }

    MUTATION_LOCKS
        .write()
        .entry(box_name.to_string())
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

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
    db::init(&path)
}

#[frb(sync)]
pub fn open_box(name: String, encryption_key: Option<String>) -> Result<(), String> {
    let mutation_lock = mutation_lock(&name);
    let _mutation_guard = mutation_lock.lock();
    db::open(&name, encryption_key.as_deref())
}

#[frb(sync)]
pub fn close_box(name: String) -> Result<(), String> {
    let mutation_lock = mutation_lock(&name);
    let _mutation_guard = mutation_lock.lock();
    db::close(&name);
    Ok(())
}

#[frb(sync)]
pub fn delete_box(name: String) -> Result<(), String> {
    let mutation_lock = mutation_lock(&name);
    let _mutation_guard = mutation_lock.lock();
    db::delete_box(&name)?;
    WATCHERS.write().remove(&name);
    Ok(())
}

#[frb(sync)]
pub fn encrypt_box(name: String, encryption_key: String) -> Result<(), String> {
    #[cfg(all(feature = "encryption", feature = "maintenance"))]
    {
        let mutation_lock = mutation_lock(&name);
        let _mutation_guard = mutation_lock.lock();
        db::encrypt_box(&name, &encryption_key)
    }

    #[cfg(not(all(feature = "encryption", feature = "maintenance")))]
    {
        let _ = (name, encryption_key);
        Err(
            "plaintext encryption migration requires native features 'encryption' and 'maintenance'"
                .to_string(),
        )
    }
}

#[frb(sync)]
pub fn box_exists(name: String) -> Result<bool, String> {
    db::box_exists(&name)
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

    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    db::len(&box_name)?;
    WATCHERS
        .write()
        .entry(box_name)
        .or_default()
        .insert(watcher_id, sink);
    Ok(())
}

#[frb(sync)]
pub fn unwatch_box(box_name: String, watcher_id: String) -> Result<(), String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
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
}

pub fn put(box_name: String, key: String, value: Vec<u8>) -> Result<(), String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    db::put(&box_name, &key, &value)?;
    emit_event(NativeBoxEvent {
        box_name,
        event_type: NativeBoxEventType::Put,
        key: Some(key),
        value: Some(value),
    });
    Ok(())
}

pub fn put_all(box_name: String, entries: Vec<(String, Vec<u8>)>) -> Result<(), String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    db::put_all(&box_name, &entries)?;
    for (key, value) in entries {
        emit_event(NativeBoxEvent {
            box_name: box_name.clone(),
            event_type: NativeBoxEventType::Put,
            key: Some(key),
            value: Some(value),
        });
    }
    Ok(())
}

#[frb(sync)]
pub fn get(box_name: String, key: String) -> Result<Option<Vec<u8>>, String> {
    db::get(&box_name, &key)
}

#[frb(sync)]
pub fn contains_key(box_name: String, key: String) -> Result<bool, String> {
    db::contains_key(&box_name, &key)
}

pub fn delete(box_name: String, key: String) -> Result<(), String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    db::delete(&box_name, &key)?;
    emit_event(NativeBoxEvent {
        box_name,
        event_type: NativeBoxEventType::Delete,
        key: Some(key),
        value: None,
    });
    Ok(())
}

pub fn delete_all(box_name: String, keys: Vec<String>) -> Result<Vec<String>, String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    let deleted = db::delete_all(&box_name, &keys)?;
    for key in &deleted {
        emit_event(NativeBoxEvent {
            box_name: box_name.clone(),
            event_type: NativeBoxEventType::Delete,
            key: Some(key.clone()),
            value: None,
        });
    }
    Ok(deleted)
}

pub fn clear(box_name: String) -> Result<(), String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    db::clear(&box_name)?;
    emit_event(NativeBoxEvent {
        box_name,
        event_type: NativeBoxEventType::Clear,
        key: None,
        value: None,
    });
    Ok(())
}

pub fn compact(box_name: String) -> Result<bool, String> {
    #[cfg(feature = "maintenance")]
    {
        let mutation_lock = mutation_lock(&box_name);
        let _mutation_guard = mutation_lock.lock();
        db::compact(&box_name)
    }

    #[cfg(not(feature = "maintenance"))]
    {
        let _ = box_name;
        Err("compaction requires native feature 'maintenance'".to_string())
    }
}

pub fn scan_query(
    box_name: String,
    query_payload: Vec<u8>,
) -> Result<Vec<NativeQueryRecord>, String> {
    #[cfg(feature = "full")]
    {
        let spec = query::decode_query(&query_payload)?;
        let (database, encryption) = db::database(&box_name)?;
        let read = database.begin_read().map_err(|e| e.to_string())?;
        let mut keys = match index::candidate_keys(&read, &spec.filter)? {
            Some(keys) => keys,
            None => db::query_all_keys(&read)?,
        };
        keys.sort();
        keys.dedup();

        if spec.sort_by.is_empty() {
            let mut matched = 0usize;
            let mut results = Vec::new();
            for key in keys {
                let Some(value) = db::query_get(&read, &encryption, &key)? else {
                    continue;
                };
                if !query::matches_record(&value, &spec.filter)? {
                    continue;
                }
                if matched < spec.offset {
                    matched += 1;
                    continue;
                }
                results.push(NativeQueryRecord { key, value });
                matched += 1;
                if spec.limit.is_some_and(|limit| results.len() >= limit) {
                    break;
                }
            }
            return Ok(results);
        }

        let mut sortable = Vec::new();
        for key in keys {
            let Some(value) = db::query_get(&read, &encryption, &key)? else {
                continue;
            };
            if !query::matches_record(&value, &spec.filter)? {
                continue;
            }
            let sort_values = query::sort_values(&value, &spec.sort_by)?;
            sortable.push((key, value, sort_values));
        }

        let sort_rows = sortable
            .iter()
            .map(|(_, _, values)| values.clone())
            .collect::<Vec<_>>();
        query::validate_sort_rows(&sort_rows, &spec.sort_by)?;
        sortable.sort_by(|left, right| {
            query::compare_sort_rows(&left.2, &left.0, &right.2, &right.0, &spec.sort_by)
        });

        let limit = spec.limit.unwrap_or(usize::MAX);
        Ok(sortable
            .into_iter()
            .skip(spec.offset)
            .take(limit)
            .map(|(key, value, _)| NativeQueryRecord { key, value })
            .collect())
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (box_name, query_payload);
        Err("native query execution requires the full profile".to_string())
    }
}

pub fn create_index(box_name: String, name: String, field: String) -> Result<(), String> {
    #[cfg(feature = "full")]
    {
        let mutation_lock = mutation_lock(&box_name);
        let _mutation_guard = mutation_lock.lock();
        let (db, encryption) = db::database(&box_name)?;
        index::create(&db, &encryption, &name, &field)
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (box_name, name, field);
        Err("persisted indexes require the full profile".to_string())
    }
}

pub fn list_indexes(box_name: String) -> Result<Vec<NativeIndexDefinition>, String> {
    #[cfg(feature = "full")]
    {
        let (db, _) = db::database(&box_name)?;
        index::list(&db).map(|definitions| {
            definitions
                .into_iter()
                .map(|(name, field)| NativeIndexDefinition { name, field })
                .collect()
        })
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = box_name;
        Err("persisted indexes require the full profile".to_string())
    }
}

pub fn drop_index(box_name: String, name: String) -> Result<bool, String> {
    #[cfg(feature = "full")]
    {
        let mutation_lock = mutation_lock(&box_name);
        let _mutation_guard = mutation_lock.lock();
        let (db, _) = db::database(&box_name)?;
        index::drop_index(&db, &name)
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (box_name, name);
        Err("persisted indexes require the full profile".to_string())
    }
}

pub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {
    db::all_keys(&box_name)
}

pub fn length(box_name: String) -> Result<u64, String> {
    db::len(&box_name)
}
