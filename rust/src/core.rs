use std::{collections::HashMap, path::Path, sync::Arc};

use once_cell::sync::Lazy;
use parking_lot::{Mutex, RwLock};

use crate::db;
#[cfg(feature = "full")]
use crate::{index, query};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum BoxEventType {
    Put,
    Delete,
    Clear,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BoxEvent {
    pub box_name: String,
    pub event_type: BoxEventType,
    pub key: Option<String>,
    pub value: Option<Vec<u8>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct QueryRecord {
    pub key: String,
    pub value: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BatchRecord {
    pub key: String,
    pub value: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct IndexDefinition {
    pub name: String,
    pub field: String,
}

type MutationLocks = HashMap<String, Arc<Mutex<()>>>;

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

pub(crate) fn with_box_mutation_lock<T>(
    box_name: &str,
    operation: impl FnOnce() -> Result<T, String>,
) -> Result<T, String> {
    let mutation_lock = mutation_lock(box_name);
    let _mutation_guard = mutation_lock.lock();
    operation()
}

pub fn init(path: &Path) -> Result<(), String> {
    db::init(path.to_string_lossy().as_ref())
}

pub fn open_box(name: &str, encryption_key: Option<&str>) -> Result<(), String> {
    with_box_mutation_lock(name, || db::open(name, encryption_key))
}

pub fn close_box(name: &str) -> Result<(), String> {
    with_box_mutation_lock(name, || {
        db::close(name);
        Ok(())
    })
}

pub fn delete_box(name: &str) -> Result<(), String> {
    with_box_mutation_lock(name, || db::delete_box(name))
}

pub fn encrypt_box(name: &str, encryption_key: &str) -> Result<(), String> {
    #[cfg(all(feature = "encryption", feature = "maintenance"))]
    {
        with_box_mutation_lock(name, || db::encrypt_box(name, encryption_key))
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

pub fn box_exists(name: &str) -> Result<bool, String> {
    db::box_exists(name)
}

pub fn validate_open_box(name: &str) -> Result<(), String> {
    with_box_mutation_lock(name, || db::len(name).map(|_| ()))
}

pub fn put(box_name: &str, key: String, value: Vec<u8>) -> Result<BoxEvent, String> {
    with_box_mutation_lock(box_name, || {
        db::put(box_name, &key, &value)?;
        Ok(BoxEvent {
            box_name: box_name.to_string(),
            event_type: BoxEventType::Put,
            key: Some(key),
            value: Some(value),
        })
    })
}

pub fn put_all(
    box_name: &str,
    entries: Vec<(String, Vec<u8>)>,
) -> Result<Vec<BoxEvent>, String> {
    with_box_mutation_lock(box_name, || {
        db::put_all(box_name, &entries)?;
        Ok(entries
            .into_iter()
            .map(|(key, value)| BoxEvent {
                box_name: box_name.to_string(),
                event_type: BoxEventType::Put,
                key: Some(key),
                value: Some(value),
            })
            .collect())
    })
}

pub fn get(box_name: &str, key: &str) -> Result<Option<Vec<u8>>, String> {
    db::get(box_name, key)
}

pub fn contains_key(box_name: &str, key: &str) -> Result<bool, String> {
    db::contains_key(box_name, key)
}

pub fn get_all(box_name: &str, keys: &[String]) -> Result<Vec<BatchRecord>, String> {
    db::get_all(box_name, keys).map(|records| {
        records
            .into_iter()
            .map(|(key, value)| BatchRecord { key, value })
            .collect()
    })
}

pub fn delete(box_name: &str, key: String) -> Result<BoxEvent, String> {
    with_box_mutation_lock(box_name, || {
        db::delete(box_name, &key)?;
        Ok(BoxEvent {
            box_name: box_name.to_string(),
            event_type: BoxEventType::Delete,
            key: Some(key),
            value: None,
        })
    })
}

pub fn delete_all(
    box_name: &str,
    keys: &[String],
) -> Result<(Vec<String>, Vec<BoxEvent>), String> {
    with_box_mutation_lock(box_name, || {
        let deleted = db::delete_all(box_name, keys)?;
        let events = deleted
            .iter()
            .cloned()
            .map(|key| BoxEvent {
                box_name: box_name.to_string(),
                event_type: BoxEventType::Delete,
                key: Some(key),
                value: None,
            })
            .collect();
        Ok((deleted, events))
    })
}

pub fn clear(box_name: &str) -> Result<BoxEvent, String> {
    with_box_mutation_lock(box_name, || {
        db::clear(box_name)?;
        Ok(BoxEvent {
            box_name: box_name.to_string(),
            event_type: BoxEventType::Clear,
            key: None,
            value: None,
        })
    })
}

pub fn compact(box_name: &str) -> Result<bool, String> {
    #[cfg(feature = "maintenance")]
    {
        with_box_mutation_lock(box_name, || db::compact(box_name))
    }

    #[cfg(not(feature = "maintenance"))]
    {
        let _ = box_name;
        Err("compaction requires native feature 'maintenance'".to_string())
    }
}

#[cfg(feature = "full")]
pub fn query(box_name: &str, spec: &query::QuerySpec) -> Result<Vec<QueryRecord>, String> {
    let (database, encryption) = db::database(box_name)?;
    let read = database.begin_read().map_err(|e| e.to_string())?;
    let mut keys = match index::candidate_keys(&read, encryption.as_ref(), &spec.filter)? {
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
            results.push(QueryRecord { key, value });
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
        .map(|(key, value, _)| QueryRecord { key, value })
        .collect())
}

pub fn create_index(box_name: &str, name: &str, field: &str) -> Result<(), String> {
    #[cfg(feature = "full")]
    {
        with_box_mutation_lock(box_name, || {
            let (database, encryption) = db::database(box_name)?;
            index::create(&database, &encryption, name, field)
        })
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (box_name, name, field);
        Err("persisted indexes require the full profile".to_string())
    }
}

pub fn list_indexes(box_name: &str) -> Result<Vec<IndexDefinition>, String> {
    #[cfg(feature = "full")]
    {
        let (database, _) = db::database(box_name)?;
        index::list(&database).map(|definitions| {
            definitions
                .into_iter()
                .map(|(name, field)| IndexDefinition { name, field })
                .collect()
        })
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = box_name;
        Err("persisted indexes require the full profile".to_string())
    }
}

pub fn drop_index(box_name: &str, name: &str) -> Result<bool, String> {
    #[cfg(feature = "full")]
    {
        with_box_mutation_lock(box_name, || {
            let (database, _) = db::database(box_name)?;
            index::drop_index(&database, name)
        })
    }

    #[cfg(not(feature = "full"))]
    {
        let _ = (box_name, name);
        Err("persisted indexes require the full profile".to_string())
    }
}

pub fn all_keys(box_name: &str) -> Result<Vec<String>, String> {
    db::all_keys(box_name)
}

pub fn len(box_name: &str) -> Result<u64, String> {
    db::len(box_name)
}
