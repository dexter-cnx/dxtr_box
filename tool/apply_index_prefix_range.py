from pathlib import Path
import re

path = Path('rust/src/index.rs')
text = path.read_text()

lookup_pattern = re.compile(r'''fn lookup_candidate\(\n    db: &Database,\n    index_name: &str,\n    candidate: &query::IndexCandidate,\n\) -> Result<Vec<String>, String> \{.*?\n\}\n\nfn decode_candidate_entry''', re.S)
lookup_replacement = r'''fn lookup_candidate(
    db: &Database,
    index_name: &str,
    candidate: &query::IndexCandidate,
) -> Result<Vec<String>, String> {
    let prefix = index_prefix(index_name);
    let upper = prefix_successor(&prefix)
        .ok_or_else(|| "persisted index prefix has no lexicographic successor".to_string())?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
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

fn decode_candidate_entry'''
text, count = lookup_pattern.subn(lookup_replacement, text, count=1)
assert count == 1, 'lookup_candidate block not found'

remove_pattern = re.compile(r'''fn remove_index_entries\(write: &WriteTransaction, index_name: &str\) -> Result<\(\), String> \{.*?\n\}\n\nfn entry_key''', re.S)
remove_replacement = r'''fn remove_index_entries(write: &WriteTransaction, index_name: &str) -> Result<(), String> {
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

fn entry_key'''
text, count = remove_pattern.subn(remove_replacement, text, count=1)
assert count == 1, 'remove_index_entries block not found'

needle = '''fn index_prefix(index_name: &str) -> Vec<u8> {
    let mut prefix = Vec::with_capacity(4 + index_name.len());
    push_component(&mut prefix, index_name.as_bytes());
    prefix
}

fn push_component'''
replacement = '''fn index_prefix(index_name: &str) -> Vec<u8> {
    let mut prefix = Vec::with_capacity(4 + index_name.len());
    push_component(&mut prefix, index_name.as_bytes());
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

fn push_component'''
assert needle in text, 'index_prefix insertion point not found'
text = text.replace(needle, replacement, 1)

text += r'''

#[cfg(test)]
mod tests {
    use super::{index_prefix, prefix_successor};

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
    fn prefix_successor_carries_and_truncates() {
        assert_eq!(
            prefix_successor(&[0x01, 0x7f, 0xff]),
            Some(vec![0x01, 0x80])
        );
        assert_eq!(prefix_successor(&[0xff, 0xff]), None);
    }
}
'''

path.write_text(text)
