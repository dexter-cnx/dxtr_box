from pathlib import Path
import re

query_path = Path('rust/src/query.rs')
index_path = Path('rust/src/index.rs')
test_path = Path('rust/tests/query_index.rs')

query = query_path.read_text()

candidate_block = re.compile(r"pub fn equality_index_candidates\(filter: &Filter\) -> Result<Vec<\(String, Vec<u8>\)>, String> \{.*?\n\}\n\nfn parse_filter", re.S)
replacement = r'''#[derive(Debug, Clone)]
pub struct IndexCandidate {
    pub field: String,
    pub op: CompareOp,
    pub value: Vec<u8>,
    pub upper_value: Option<Vec<u8>>,
}

pub fn index_candidates(filter: &Filter) -> Result<Vec<IndexCandidate>, String> {
    match filter {
        Filter::Comparison(comparison) => {
            let Some(value) = comparison.value.as_ref() else {
                return Ok(Vec::new());
            };

            let eligible = match comparison.op {
                CompareOp::Equal => is_index_scalar(value),
                CompareOp::GreaterThan
                | CompareOp::GreaterThanOrEqual
                | CompareOp::LessThan
                | CompareOp::LessThanOrEqual => is_ordered_index_scalar(value),
                CompareOp::Between => {
                    is_ordered_index_scalar(value)
                        && comparison
                            .upper_value
                            .as_ref()
                            .is_some_and(is_ordered_index_scalar)
                }
                CompareOp::NotEqual | CompareOp::IsNull | CompareOp::IsNotNull => false,
            };
            if !eligible {
                return Ok(Vec::new());
            }

            let mut encoded = Vec::new();
            rmpv::encode::write_value(&mut encoded, value).map_err(|e| e.to_string())?;
            let upper_value = comparison
                .upper_value
                .as_ref()
                .map(|upper| {
                    let mut encoded = Vec::new();
                    rmpv::encode::write_value(&mut encoded, upper).map_err(|e| e.to_string())?;
                    Ok(encoded)
                })
                .transpose()?;
            Ok(vec![IndexCandidate {
                field: comparison.field.clone(),
                op: comparison.op,
                value: encoded,
                upper_value,
            }])
        }
        Filter::Group {
            op: LogicalOp::And,
            filters,
        } => {
            let mut candidates = Vec::new();
            for filter in filters {
                candidates.extend(index_candidates(filter)?);
            }
            Ok(candidates)
        }
        Filter::Group {
            op: LogicalOp::Or, ..
        } => Ok(Vec::new()),
    }
}

pub fn index_candidate_matches(
    scalar: &[u8],
    candidate: &IndexCandidate,
) -> Result<bool, String> {
    let actual = decode_messagepack_value(scalar, "invalid persisted index scalar")?;
    let expected = decode_messagepack_value(&candidate.value, "invalid query index candidate")?;
    let upper = candidate
        .upper_value
        .as_deref()
        .map(|bytes| decode_messagepack_value(bytes, "invalid upper query index candidate"))
        .transpose()?;

    Ok(match candidate.op {
        CompareOp::Equal => values_equal(&actual, &expected),
        CompareOp::GreaterThan => compare(&actual, Some(&expected))? == Some(Ordering::Greater),
        CompareOp::GreaterThanOrEqual => matches!(
            compare(&actual, Some(&expected))?,
            Some(Ordering::Greater | Ordering::Equal)
        ),
        CompareOp::LessThan => compare(&actual, Some(&expected))? == Some(Ordering::Less),
        CompareOp::LessThanOrEqual => matches!(
            compare(&actual, Some(&expected))?,
            Some(Ordering::Less | Ordering::Equal)
        ),
        CompareOp::Between => {
            let Some(upper) = upper.as_ref() else {
                return Ok(false);
            };
            matches!(
                compare(&actual, Some(&expected))?,
                Some(Ordering::Greater | Ordering::Equal)
            ) && matches!(
                compare(&actual, Some(upper))?,
                Some(Ordering::Less | Ordering::Equal)
            )
        }
        CompareOp::NotEqual | CompareOp::IsNull | CompareOp::IsNotNull => false,
    })
}

fn decode_messagepack_value(bytes: &[u8], context: &str) -> Result<Value, String> {
    let mut cursor = Cursor::new(bytes);
    rmpv::decode::read_value(&mut cursor).map_err(|e| format!("{context}: {e}"))
}

fn parse_filter'''
query, count = candidate_block.subn(replacement, query, count=1)
assert count == 1, 'query candidate block not found'

query = query.replace(
    '''fn is_index_scalar(value: &Value) -> bool {
    value.is_nil()
        || value.is_bool()
        || value.as_i64().is_some()
        || value.as_u64().is_some()
        || value.as_f64().is_some()
        || value.as_str().is_some()
}
''',
    '''fn is_index_scalar(value: &Value) -> bool {
    value.is_nil()
        || value.is_bool()
        || value.as_i64().is_some()
        || value.as_u64().is_some()
        || value.as_f64().is_some()
        || value.as_str().is_some()
}

fn is_ordered_index_scalar(value: &Value) -> bool {
    value.as_i64().is_some()
        || value.as_u64().is_some()
        || value.as_f64().is_some()
        || value.as_str().is_some()
}
''')

query_path.write_text(query)

index = index_path.read_text()
index = index.replace(
    'use redb::{Database, ReadableTable, TableDefinition, WriteTransaction};',
    'use std::collections::HashSet;\n\nuse redb::{Database, ReadableTable, TableDefinition, WriteTransaction};'
)

candidate_keys_block = re.compile(r"pub\(crate\) fn candidate_keys\(.*?\nfn entry_value_prefix", re.S)
index_replacement = r'''pub(crate) fn candidate_keys(
    db: &Database,
    filter: &query::Filter,
) -> Result<Option<Vec<String>>, String> {
    let candidates = query::index_candidates(filter)?;
    if candidates.is_empty() {
        return Ok(None);
    }

    let definitions = list(db)?;
    let mut candidate_sets = Vec::<HashSet<String>>::new();
    for candidate in candidates {
        let Some((index_name, _)) = definitions
            .iter()
            .find(|(_, indexed_field)| *indexed_field == candidate.field)
        else {
            continue;
        };
        candidate_sets.push(lookup_candidate(db, index_name, &candidate)?.into_iter().collect());
    }

    if candidate_sets.is_empty() {
        return Ok(None);
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
    db: &Database,
    index_name: &str,
    candidate: &query::IndexCandidate,
) -> Result<Vec<String>, String> {
    let prefix = index_prefix(index_name);
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let entries = read.open_table(INDEX_ENTRIES).map_err(|e| e.to_string())?;
    entries
        .iter()
        .map_err(|e| e.to_string())?
        .filter_map(|item| match item {
            Ok((key, _)) if key.value().starts_with(&prefix) => {
                Some(decode_candidate_entry(key.value(), prefix.len(), candidate))
            }
            Ok(_) => None,
            Err(error) => Some(Err(error.to_string())),
        })
        .filter_map(|result| match result {
            Ok(Some(key)) => Some(Ok(key)),
            Ok(None) => None,
            Err(error) => Some(Err(error)),
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

fn entry_value_prefix'''
index, count = candidate_keys_block.subn(index_replacement, index, count=1)
assert count == 1, 'index candidate block not found'
index_path.write_text(index)

tests = test_path.read_text()
insert_before = '''#[test]
fn encrypted_box_uses_scan_but_rejects_persisted_index_creation()'''
new_tests = r'''fn comparison_query(field: &str, operator: &str, value: Value, upper: Value) -> Vec<u8> {
    let comparison = dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from(field)),
        ("operator", Value::from(operator)),
        ("value", value),
        ("upperValue", upper),
    ]);
    encode(&dxtr_map(vec![
        ("where", comparison),
        ("limit", Value::Nil),
        ("offset", Value::from(0_u64)),
    ]))
}

fn result_keys(box_name: &str, payload: Vec<u8>) -> Vec<String> {
    scan_query(box_name.to_string(), payload)
        .unwrap()
        .into_iter()
        .map(|record| record.key)
        .collect()
}

#[test]
fn nested_range_index_matches_scan_for_all_ordered_operators() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("ages".to_string(), None).unwrap();

    for (key, age) in [("a", 17), ("b", 18), ("c", 22), ("d", 40), ("e", 65)] {
        put(
            "ages".to_string(),
            key.to_string(),
            person("active", age),
        )
        .unwrap();
    }

    let queries = vec![
        comparison_query(
            "profile.age",
            "greaterThan",
            Value::from(18_i64),
            Value::Nil,
        ),
        comparison_query(
            "profile.age",
            "greaterThanOrEqual",
            Value::from(18_i64),
            Value::Nil,
        ),
        comparison_query(
            "profile.age",
            "lessThan",
            Value::from(40_i64),
            Value::Nil,
        ),
        comparison_query(
            "profile.age",
            "lessThanOrEqual",
            Value::from(40_i64),
            Value::Nil,
        ),
        comparison_query(
            "profile.age",
            "between",
            Value::from(18_i64),
            Value::from(40_i64),
        ),
    ];
    let scan_results = queries
        .iter()
        .cloned()
        .map(|payload| result_keys("ages", payload))
        .collect::<Vec<_>>();

    create_index(
        "ages".to_string(),
        "by-age".to_string(),
        "profile.age".to_string(),
    )
    .unwrap();

    let indexed_results = queries
        .into_iter()
        .map(|payload| result_keys("ages", payload))
        .collect::<Vec<_>>();
    assert_eq!(indexed_results, scan_results);

    close_box("ages".to_string()).unwrap();
}

#[test]
fn and_group_intersects_multiple_persisted_indexes() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("intersection".to_string(), None).unwrap();

    for (key, status, age) in [
        ("alice", "active", 22),
        ("bob", "inactive", 35),
        ("charlie", "active", 40),
        ("teen", "active", 17),
    ] {
        put(
            "intersection".to_string(),
            key.to_string(),
            person(status, age),
        )
        .unwrap();
    }

    let scan = result_keys("intersection", query_payload());
    create_index(
        "intersection".to_string(),
        "by-status".to_string(),
        "status".to_string(),
    )
    .unwrap();
    create_index(
        "intersection".to_string(),
        "by-age".to_string(),
        "profile.age".to_string(),
    )
    .unwrap();

    let indexed = result_keys("intersection", query_payload());
    assert_eq!(indexed, scan);
    assert_eq!(indexed, vec!["alice", "charlie"]);

    close_box("intersection".to_string()).unwrap();
}

#[test]
fn encrypted_box_uses_scan_but_rejects_persisted_index_creation()'''
assert insert_before in tests, 'test insertion point not found'
tests = tests.replace(insert_before, new_tests, 1)
test_path.write_text(tests)
