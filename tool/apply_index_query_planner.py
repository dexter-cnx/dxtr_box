from pathlib import Path

# query.rs: expose conservative equality predicates that are safe to use as
# candidate narrowing. OR groups deliberately return no candidates.
path = Path('rust/src/query.rs')
text = path.read_text()
marker = 'fn parse_filter(value: &Value) -> Result<Filter, String> {\n'
insert = '''pub fn equality_index_candidates(filter: &Filter) -> Result<Vec<(String, Vec<u8>)>, String> {
    match filter {
        Filter::Comparison(comparison) => {
            if !matches!(comparison.op, CompareOp::Equal) {
                return Ok(Vec::new());
            }
            let Some(value) = comparison.value.as_ref() else {
                return Ok(Vec::new());
            };
            if !is_index_scalar(value) {
                return Ok(Vec::new());
            }
            let mut encoded = Vec::new();
            rmpv::encode::write_value(&mut encoded, value).map_err(|e| e.to_string())?;
            Ok(vec![(comparison.field.clone(), encoded)])
        }
        Filter::Group {
            op: LogicalOp::And,
            filters,
        } => {
            let mut candidates = Vec::new();
            for filter in filters {
                candidates.extend(equality_index_candidates(filter)?);
            }
            Ok(candidates)
        }
        Filter::Group {
            op: LogicalOp::Or,
            ..
        } => Ok(Vec::new()),
    }
}

'''
if marker not in text:
    raise SystemExit('query parse_filter marker not found')
text = text.replace(marker, insert + marker, 1)
path.write_text(text)

# index.rs: choose the first persisted index matching an eligible equality
# predicate and return record-key candidates from derived index entries.
path = Path('rust/src/index.rs')
text = path.read_text()
marker = 'pub(crate) fn drop_index(db: &Database, name: &str) -> Result<bool, String> {\n'
insert = '''pub(crate) fn candidate_keys(
    db: &Database,
    filter: &query::Filter,
) -> Result<Option<Vec<String>>, String> {
    let candidates = query::equality_index_candidates(filter)?;
    if candidates.is_empty() {
        return Ok(None);
    }

    let definitions = list(db)?;
    for (field, scalar) in candidates {
        if let Some((index_name, _)) = definitions.iter().find(|(_, indexed_field)| *indexed_field == field) {
            return lookup_equal(db, index_name, &scalar).map(Some);
        }
    }
    Ok(None)
}

fn lookup_equal(db: &Database, index_name: &str, scalar: &[u8]) -> Result<Vec<String>, String> {
    let prefix = entry_value_prefix(index_name, scalar);
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let entries = read.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    entries
        .iter()
        .map_err(|e| e.to_string())?
        .filter_map(|item| match item {
            Ok((key, _)) if key.value().starts_with(&prefix) => {
                Some(decode_record_key(key.value(), prefix.len()))
            }
            Ok(_) => None,
            Err(error) => Some(Err(error.to_string())),
        })
        .collect()
}

fn entry_value_prefix(index_name: &str, scalar: &[u8]) -> Vec<u8> {
    let mut prefix = index_prefix(index_name);
    push_component(&mut prefix, scalar);
    prefix
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

'''
if marker not in text:
    raise SystemExit('index drop marker not found')
text = text.replace(marker, insert + marker, 1)
path.write_text(text)

# api.rs: use index candidates when the conservative planner finds a usable
# persisted equality index. Full predicate evaluation remains authoritative.
path = Path('rust/src/api.rs')
text = path.read_text()
old = '''        let spec = query::decode_query(&query_payload)?;
        let mut keys = db::all_keys(&box_name)?;
        keys.sort();
'''
new = '''        let spec = query::decode_query(&query_payload)?;
        let (database, _) = db::database(&box_name)?;
        let mut keys = match index::candidate_keys(&database, &spec.filter)? {
            Some(keys) => keys,
            None => db::all_keys(&box_name)?,
        };
        keys.sort();
        keys.dedup();
'''
if old not in text:
    raise SystemExit('api scan marker not found')
text = text.replace(old, new, 1)
path.write_text(text)

# Integration equivalence: query before index creation must use scan; the same
# query after creation can use the persisted equality index and must be exact.
path = Path('rust/tests/query_index.rs')
text = path.read_text()
old = '''    assert_eq!(definitions[0].name, "by-status");
    assert_eq!(definitions[0].field, "status");

    close_box("people".to_string()).unwrap();
'''
new = '''    assert_eq!(definitions[0].name, "by-status");
    assert_eq!(definitions[0].field, "status");

    let indexed_results = scan_query("people".to_string(), query_payload()).unwrap();
    assert_eq!(
        indexed_results
            .iter()
            .map(|record| record.key.as_str())
            .collect::<Vec<_>>(),
        vec!["alice", "charlie"]
    );
    assert_eq!(
        indexed_results
            .iter()
            .map(|record| record.value.as_slice())
            .collect::<Vec<_>>(),
        results
            .iter()
            .map(|record| record.value.as_slice())
            .collect::<Vec<_>>()
    );

    put(
        "people".to_string(),
        "alice".to_string(),
        person("inactive", 22),
    )
    .unwrap();
    let after_indexed_mutation = scan_query("people".to_string(), query_payload()).unwrap();
    assert_eq!(
        after_indexed_mutation
            .iter()
            .map(|record| record.key.as_str())
            .collect::<Vec<_>>(),
        vec!["charlie"]
    );

    close_box("people".to_string()).unwrap();
'''
if old not in text:
    raise SystemExit('query index test marker not found')
text = text.replace(old, new, 1)
path.write_text(text)
