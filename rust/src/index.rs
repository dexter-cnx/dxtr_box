use redb::{Database, ReadableTable, TableDefinition, WriteTransaction};

use crate::{db::EncryptionState, query};

const INDEX_DEFINITIONS: TableDefinition<&str, &str> = TableDefinition::new("index_definitions");
const INDEX_ENTRIES: TableDefinition<&[u8], &[u8]> = TableDefinition::new("index_entries");
const EMPTY_VALUE: &[u8] = &[];

pub(crate) fn ensure_tables(db: &Database) -> Result<(), String> {
    let write = db.begin_write().map_err(|e| e.to_string())?;
    write
        .open_table(INDEX_DEFINITIONS)
        .map_err(|e| e.to_string())?;
    write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    write.commit().map_err(|e| e.to_string())
}

pub(crate) fn create(
    db: &Database,
    encryption: &EncryptionState,
    name: &str,
    field: &str,
) -> Result<(), String> {
    query::validate_index_definition(name, field)?;
    if encryption.is_encrypted() {
        return Err(
            "persisted indexes are not yet supported for encrypted boxes; native scan queries remain available"
                .to_string(),
        );
    }

    let write = db.begin_write().map_err(|e| e.to_string())?;
    {
        let mut definitions = write
            .open_table(INDEX_DEFINITIONS)
            .map_err(|e| e.to_string())?;
        if let Some(existing) = definitions.get(name).map_err(|e| e.to_string())? {
            if existing.value() == field {
                return Ok(());
            }
            return Err(format!(
                "index '{name}' already exists for field '{}'",
                existing.value()
            ));
        }

        let data = write
            .open_table(super::db::DATA)
            .map_err(|e| e.to_string())?;
        let mut derived = Vec::new();
        for item in data.iter().map_err(|e| e.to_string())? {
            let (record_key, value) = item.map_err(|e| e.to_string())?;
            if let Some(scalar) = query::index_scalar_key(value.value(), field)? {
                derived.push(entry_key(name, &scalar, record_key.value()));
            }
        }
        drop(data);

        definitions.insert(name, field).map_err(|e| e.to_string())?;
        drop(definitions);

        let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
        for key in derived {
            entries
                .insert(key.as_slice(), EMPTY_VALUE)
                .map_err(|e| e.to_string())?;
        }
    }
    write.commit().map_err(|e| e.to_string())
}

pub(crate) fn list(db: &Database) -> Result<Vec<(String, String)>, String> {
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read
        .open_table(INDEX_DEFINITIONS)
        .map_err(|e| e.to_string())?;
    table
        .iter()
        .map_err(|e| e.to_string())?
        .map(|item| {
            item.map(|(name, field)| (name.value().to_string(), field.value().to_string()))
                .map_err(|e| e.to_string())
        })
        .collect()
}

pub(crate) fn drop_index(db: &Database, name: &str) -> Result<bool, String> {
    let write = db.begin_write().map_err(|e| e.to_string())?;
    let removed = {
        let mut definitions = write
            .open_table(INDEX_DEFINITIONS)
            .map_err(|e| e.to_string())?;
        let removed = definitions
            .remove(name)
            .map_err(|e| e.to_string())?
            .is_some();
        removed
    };
    if !removed {
        return Ok(false);
    }

    remove_index_entries(&write, name)?;
    write.commit().map_err(|e| e.to_string())?;
    Ok(true)
}

pub(crate) fn maintain_put(
    write: &WriteTransaction,
    record_key: &str,
    old_value: Option<&[u8]>,
    new_value: &[u8],
) -> Result<(), String> {
    let definitions = definitions(write)?;
    if definitions.is_empty() {
        return Ok(());
    }

    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    for (index_name, field) in definitions {
        if let Some(old) = old_value {
            if let Some(scalar) = query::index_scalar_key(old, &field)? {
                entries
                    .remove(entry_key(&index_name, &scalar, record_key).as_slice())
                    .map_err(|e| e.to_string())?;
            }
        }
        if let Some(scalar) = query::index_scalar_key(new_value, &field)? {
            entries
                .insert(
                    entry_key(&index_name, &scalar, record_key).as_slice(),
                    EMPTY_VALUE,
                )
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

pub(crate) fn maintain_delete(
    write: &WriteTransaction,
    record_key: &str,
    old_value: &[u8],
) -> Result<(), String> {
    let definitions = definitions(write)?;
    if definitions.is_empty() {
        return Ok(());
    }

    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    for (index_name, field) in definitions {
        if let Some(scalar) = query::index_scalar_key(old_value, &field)? {
            entries
                .remove(entry_key(&index_name, &scalar, record_key).as_slice())
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

pub(crate) fn clear_entries(write: &WriteTransaction) -> Result<(), String> {
    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    let keys = entries
        .iter()
        .map_err(|e| e.to_string())?
        .map(|item| {
            item.map(|(key, _)| key.value().to_vec())
                .map_err(|e| e.to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;
    for key in keys {
        entries.remove(key.as_slice()).map_err(|e| e.to_string())?;
    }
    Ok(())
}

pub(crate) fn has_definitions(db: &Database) -> Result<bool, String> {
    Ok(!list(db)?.is_empty())
}

fn definitions(write: &WriteTransaction) -> Result<Vec<(String, String)>, String> {
    let table = write
        .open_table(INDEX_DEFINITIONS)
        .map_err(|e| e.to_string())?;
    table
        .iter()
        .map_err(|e| e.to_string())?
        .map(|item| {
            item.map(|(name, field)| (name.value().to_string(), field.value().to_string()))
                .map_err(|e| e.to_string())
        })
        .collect()
}

fn remove_index_entries(write: &WriteTransaction, index_name: &str) -> Result<(), String> {
    let prefix = index_prefix(index_name);
    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    let keys = entries
        .iter()
        .map_err(|e| e.to_string())?
        .filter_map(|item| match item {
            Ok((key, _)) if key.value().starts_with(&prefix) => Some(Ok(key.value().to_vec())),
            Ok(_) => None,
            Err(error) => Some(Err(error.to_string())),
        })
        .collect::<Result<Vec<_>, String>>()?;
    for key in keys {
        entries.remove(key.as_slice()).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn entry_key(index_name: &str, scalar: &[u8], record_key: &str) -> Vec<u8> {
    let name = index_name.as_bytes();
    let record = record_key.as_bytes();
    let mut key = Vec::with_capacity(12 + name.len() + scalar.len() + record.len());
    push_component(&mut key, name);
    push_component(&mut key, scalar);
    push_component(&mut key, record);
    key
}

fn index_prefix(index_name: &str) -> Vec<u8> {
    let mut prefix = Vec::with_capacity(4 + index_name.len());
    push_component(&mut prefix, index_name.as_bytes());
    prefix
}

fn push_component(output: &mut Vec<u8>, value: &[u8]) {
    let len = u32::try_from(value.len()).expect("index key component length fits u32");
    output.extend_from_slice(&len.to_be_bytes());
    output.extend_from_slice(value);
}
