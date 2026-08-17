use std::collections::HashSet;

use redb::{Database, ReadTransaction, ReadableTable, TableDefinition, WriteTransaction};

use crate::{crypto, db::EncryptionState, index_token, query};

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
            let record_key = record_key.value();
            let plaintext = decode_index_value(encryption, record_key, value.value())?;
            if let Some(scalar) = query::index_scalar_key(&plaintext, field)? {
                let persisted = persisted_scalar(encryption, name, field, &scalar)?;
                derived.push(entry_key(name, &persisted, record_key));
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

fn list_in_read(read: &ReadTransaction) -> Result<Vec<(String, String)>, String> {
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

fn select_index_candidates(
    definitions: &[(String, String)],
    candidates: Vec<query::IndexCandidate>,
) -> Vec<(String, query::IndexCandidate)> {
    candidates
        .into_iter()
        .filter_map(|candidate| {
            definitions
                .iter()
                .filter(|(_, indexed_field)| *indexed_field == candidate.field)
                .min_by(|(left_name, _), (right_name, _)| left_name.cmp(right_name))
                .map(|(index_name, _)| (index_name.clone(), candidate))
        })
        .collect()
}

pub(crate) fn candidate_keys(
    read: &ReadTransaction,
    encryption: &EncryptionState,
    filter: &query::Filter,
) -> Result<Option<Vec<String>>, String> {
    let mut candidates = query::index_candidates(filter)?;
    if encryption.is_encrypted() {
        candidates.retain(|candidate| matches!(candidate.op, query::CompareOp::Equal));
    }
    if candidates.is_empty() {
        return Ok(None);
    }

    let definitions = list_in_read(read)?;
    let selections = select_index_candidates(&definitions, candidates);
    if selections.is_empty() {
        return Ok(None);
    }

    let mut candidate_sets = Vec::<HashSet<String>>::with_capacity(selections.len());
    for (index_name, candidate) in selections {
        candidate_sets.push(
            lookup_candidate(read, encryption, &index_name, &candidate)?
                .into_iter()
                .collect(),
        );
    }

    candidate_sets.sort_by_key(HashSet::len);
    let mut intersection = candidate_sets.remove(0);
    for candidates in candidate_sets {
        intersection.retain(|key| candidates.contains(key));
        if intersection.is_empty() {
            break;
        }
    }
    Ok(Some(intersection.into_iter().collect()))
}

fn lookup_candidate(
    read: &ReadTransaction,
    encryption: &EncryptionState,
    index_name: &str,
    candidate: &query::IndexCandidate,
) -> Result<Vec<String>, String> {
    if encryption.is_encrypted() {
        if !matches!(candidate.op, query::CompareOp::Equal) {
            return Err("encrypted persisted indexes support equality narrowing only".to_string());
        }
        let scalar = persisted_scalar(
            encryption,
            index_name,
            &candidate.field,
            &candidate.value,
        )?;
        return lookup_exact_scalar(read, index_name, &scalar);
    }

    let prefix = index_prefix(index_name);
    let upper = prefix_successor(&prefix)
        .ok_or_else(|| "persisted index prefix has no lexicographic successor".to_string())?;
    let entries = read.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    entries
        .range(prefix.as_slice()..upper.as_slice())
        .map_err(|e| e.to_string())?
        .map(|item| {
            let (key, _) = item.map_err(|e| e.to_string())?;
            decode_candidate_entry(key.value(), prefix.len(), candidate)
        })
        .filter_map(|result| match result {
            Ok(Some(key)) => Some(Ok(key)),
            Ok(None) => None,
            Err(error) => Some(Err(error)),
        })
        .collect()
}

fn lookup_exact_scalar(
    read: &ReadTransaction,
    index_name: &str,
    scalar: &[u8],
) -> Result<Vec<String>, String> {
    let prefix = index_scalar_prefix(index_name, scalar);
    let upper = prefix_successor(&prefix)
        .ok_or_else(|| "persisted index scalar prefix has no lexicographic successor".to_string())?;
    let entries = read.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    entries
        .range(prefix.as_slice()..upper.as_slice())
        .map_err(|e| e.to_string())?
        .map(|item| {
            let (key, _) = item.map_err(|e| e.to_string())?;
            decode_record_key(key.value(), prefix.len())
        })
        .collect()
}

fn decode_candidate_entry(
    key: &[u8],
    scalar_offset: usize,
    candidate: &query::IndexCandidate,
) -> Result<Option<String>, String> {
    let (scalar, record_offset) = decode_component(key, scalar_offset, "scalar")?;
    if !query::index_candidate_matches(scalar, candidate)? {
        return Ok(None);
    }
    decode_record_key(key, record_offset).map(Some)
}

fn decode_component<'a>(
    key: &'a [u8],
    offset: usize,
    label: &str,
) -> Result<(&'a [u8], usize), String> {
    let length_bytes = key
        .get(offset..offset + 4)
        .ok_or_else(|| format!("invalid persisted index entry {label} length"))?;
    let length = u32::from_be_bytes(
        length_bytes
            .try_into()
            .map_err(|_| format!("invalid persisted index entry {label} length"))?,
    ) as usize;
    let start = offset + 4;
    let end = start
        .checked_add(length)
        .ok_or_else(|| format!("invalid persisted index entry {label} length"))?;
    let value = key
        .get(start..end)
        .ok_or_else(|| format!("invalid persisted index entry {label} encoding"))?;
    Ok((value, end))
}

fn decode_record_key(key: &[u8], offset: usize) -> Result<String, String> {
    let length_bytes = key
        .get(offset..offset + 4)
        .ok_or_else(|| "invalid persisted index entry record-key length".to_string())?;
    let length = u32::from_be_bytes(
        length_bytes
            .try_into()
            .map_err(|_| "invalid persisted index entry record-key length".to_string())?,
    ) as usize;
    let start = offset + 4;
    let end = start
        .checked_add(length)
        .ok_or_else(|| "invalid persisted index entry record-key length".to_string())?;
    if end != key.len() {
        return Err("invalid persisted index entry record-key encoding".to_string());
    }
    std::str::from_utf8(
        key.get(start..end)
            .ok_or_else(|| "invalid persisted index entry record-key encoding".to_string())?,
    )
    .map(str::to_string)
    .map_err(|_| "persisted index entry record key is not UTF-8".to_string())
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
    encryption: &EncryptionState,
    record_key: &str,
    old_value: Option<&[u8]>,
    new_value: &[u8],
) -> Result<(), String> {
    let definitions = definitions(write)?;
    if definitions.is_empty() {
        return Ok(());
    }

    let old_plaintext = old_value
        .map(|value| decode_index_value(encryption, record_key, value))
        .transpose()?;
    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    for (index_name, field) in definitions {
        if let Some(old) = old_plaintext.as_deref() {
            if let Some(scalar) = query::index_scalar_key(old, &field)? {
                let persisted = persisted_scalar(encryption, &index_name, &field, &scalar)?;
                entries
                    .remove(entry_key(&index_name, &persisted, record_key).as_slice())
                    .map_err(|e| e.to_string())?;
            }
        }
        if let Some(scalar) = query::index_scalar_key(new_value, &field)? {
            let persisted = persisted_scalar(encryption, &index_name, &field, &scalar)?;
            entries
                .insert(
                    entry_key(&index_name, &persisted, record_key).as_slice(),
                    EMPTY_VALUE,
                )
                .map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

pub(crate) fn maintain_delete(
    write: &WriteTransaction,
    encryption: &EncryptionState,
    record_key: &str,
    old_value: &[u8],
) -> Result<(), String> {
    let definitions = definitions(write)?;
    if definitions.is_empty() {
        return Ok(());
    }

    let old_plaintext = decode_index_value(encryption, record_key, old_value)?;
    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    for (index_name, field) in definitions {
        if let Some(scalar) = query::index_scalar_key(&old_plaintext, &field)? {
            let persisted = persisted_scalar(encryption, &index_name, &field, &scalar)?;
            entries
                .remove(entry_key(&index_name, &persisted, record_key).as_slice())
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
    let upper = prefix_successor(&prefix)
        .ok_or_else(|| "persisted index prefix has no lexicographic successor".to_string())?;
    let mut entries = write.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    let keys = entries
        .range(prefix.as_slice()..upper.as_slice())
        .map_err(|e| e.to_string())?
        .map(|item| {
            item.map(|(key, _)| key.value().to_vec())
                .map_err(|e| e.to_string())
        })
        .collect::<Result<Vec<_>, String>>()?;
    for key in keys {
        entries.remove(key.as_slice()).map_err(|e| e.to_string())?;
    }
    Ok(())
}

fn decode_index_value(
    encryption: &EncryptionState,
    record_key: &str,
    stored: &[u8],
) -> Result<Vec<u8>, String> {
    match encryption {
        EncryptionState::Plain => Ok(stored.to_vec()),
        EncryptionState::Encrypted { key, .. } => {
            crypto::decrypt_with_aad(key, record_key.as_bytes(), stored)
                .map_err(|_| "encrypted value authentication failed".to_string())
        }
    }
}

fn persisted_scalar(
    encryption: &EncryptionState,
    index_name: &str,
    field: &str,
    scalar: &[u8],
) -> Result<Vec<u8>, String> {
    match encryption {
        EncryptionState::Plain => Ok(scalar.to_vec()),
        EncryptionState::Encrypted { key, .. } => {
            index_token::encrypted_equality_token(key, index_name, field, scalar)
        }
    }
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

fn index_scalar_prefix(index_name: &str, scalar: &[u8]) -> Vec<u8> {
    let mut prefix = Vec::with_capacity(8 + index_name.len() + scalar.len());
    push_component(&mut prefix, index_name.as_bytes());
    push_component(&mut prefix, scalar);
    prefix
}

fn prefix_successor(prefix: &[u8]) -> Option<Vec<u8>> {
    let mut upper = prefix.to_vec();
    for index in (0..upper.len()).rev() {
        if upper[index] != u8::MAX {
            upper[index] += 1;
            upper.truncate(index + 1);
            return Some(upper);
        }
    }
    None
}

fn push_component(output: &mut Vec<u8>, value: &[u8]) {
    let len = u32::try_from(value.len()).expect("index key component length fits u32");
    output.extend_from_slice(&len.to_be_bytes());
    output.extend_from_slice(value);
}

#[cfg(test)]
mod tests {
    use super::{index_prefix, index_scalar_prefix, prefix_successor, select_index_candidates};
    use crate::query::{CompareOp, IndexCandidate};

    fn candidate(field: &str) -> IndexCandidate {
        IndexCandidate {
            field: field.to_string(),
            op: CompareOp::Equal,
            value: vec![0],
            upper_value: None,
        }
    }

    fn selected_names(
        definitions: &[(&str, &str)],
        candidates: Vec<IndexCandidate>,
    ) -> Vec<String> {
        let definitions = definitions
            .iter()
            .map(|(name, field)| (name.to_string(), field.to_string()))
            .collect::<Vec<_>>();
        select_index_candidates(&definitions, candidates)
            .into_iter()
            .map(|(name, _)| name)
            .collect()
    }

    #[test]
    fn planner_selection_requires_exact_field_match() {
        assert_eq!(
            selected_names(&[("by-age", "profile.age")], vec![candidate("profile.age")]),
            vec!["by-age"]
        );
        assert!(selected_names(&[("by-age", "profile.age")], vec![candidate("age")]).is_empty());
    }

    #[test]
    fn planner_selection_keeps_usable_subset_of_and_candidates() {
        assert_eq!(
            selected_names(
                &[("by-status", "status")],
                vec![candidate("status"), candidate("profile.age")],
            ),
            vec!["by-status"]
        );
    }

    #[test]
    fn planner_selection_keeps_multiple_usable_and_indexes() {
        assert_eq!(
            selected_names(
                &[("by-age", "profile.age"), ("by-status", "status")],
                vec![candidate("status"), candidate("profile.age")],
            ),
            vec!["by-status", "by-age"]
        );
    }

    #[test]
    fn planner_selection_is_deterministic_for_duplicate_field_indexes() {
        assert_eq!(
            selected_names(
                &[("z-status", "status"), ("a-status", "status")],
                vec![candidate("status")],
            ),
            vec!["a-status"]
        );
    }

    #[test]
    fn planner_selection_with_no_candidates_requires_scan_fallback() {
        assert!(selected_names(&[("by-status", "status")], Vec::new()).is_empty());
    }

    #[test]
    fn prefix_successor_bounds_exact_index_name_region() {
        let prefix = index_prefix("by-age");
        let upper = prefix_successor(&prefix).unwrap();

        assert!(prefix < upper);

        let mut same_index_entry = prefix.clone();
        same_index_entry.extend_from_slice(&[0, 0, 0, 1, 0x12]);
        assert!(same_index_entry >= prefix);
        assert!(same_index_entry < upper);

        let other_index = index_prefix("by-status");
        assert!(other_index < prefix || other_index >= upper);
    }

    #[test]
    fn scalar_prefix_bounds_one_exact_scalar_region() {
        let scalar = [0x10, 0x20, 0x30];
        let prefix = index_scalar_prefix("by-status", &scalar);
        let upper = prefix_successor(&prefix).unwrap();

        let mut matching = prefix.clone();
        matching.extend_from_slice(&[0, 0, 0, 3, b'k', b'e', b'y']);
        assert!(matching >= prefix);
        assert!(matching < upper);

        let other = index_scalar_prefix("by-status", &[0x10, 0x20, 0x31]);
        assert!(other < prefix || other >= upper);
    }

    #[test]
    fn prefix_successor_carries_and_truncates() {
        assert_eq!(
            prefix_successor(&[0x01, 0x7f, 0xff]),
            Some(vec![0x01, 0x80])
        );
        assert_eq!(prefix_successor(&[0xff, 0xff]), None);
    }
}
