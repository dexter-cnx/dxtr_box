from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"anchor not found in {path}: {old[:80]!r}")
    file.write_text(text.replace(old, new, 1))


# Dart public model.
replace_once(
    "lib/src/query.dart",
    "enum QueryLogicalOperator { and, or }\n\nfinal class QueryGroup extends QueryFilter {",
    """enum QueryLogicalOperator { and, or }\n\nenum QuerySortDirection { ascending, descending }\n\nenum QueryNullOrder { first, last }\n\nfinal class QuerySort {\n  QuerySort({\n    required this.field,\n    this.direction = QuerySortDirection.ascending,\n    this.nulls = QueryNullOrder.last,\n  }) {\n    _validateField(field);\n  }\n\n  final String field;\n  final QuerySortDirection direction;\n  final QueryNullOrder nulls;\n}\n\nfinal class QueryGroup extends QueryFilter {""",
)
replace_once(
    "lib/src/query.dart",
    """final class BoxQuery {\n  BoxQuery({\n    required this.where,\n    this.limit,\n    this.offset = 0,\n  }) {\n    if (limit != null && limit! <= 0) {\n      throw ArgumentError.value(limit, 'limit', 'limit must be greater than 0');\n    }\n    if (offset < 0) {\n      throw ArgumentError.value(offset, 'offset', 'offset cannot be negative');\n    }\n  }\n\n  final QueryFilter where;\n  final int? limit;\n  final int offset;\n}\n""",
    """final class BoxQuery {\n  BoxQuery({\n    required this.where,\n    Iterable<QuerySort> sortBy = const <QuerySort>[],\n    this.limit,\n    this.offset = 0,\n  }) : sortBy = List<QuerySort>.unmodifiable(sortBy) {\n    if (limit != null && limit! <= 0) {\n      throw ArgumentError.value(limit, 'limit', 'limit must be greater than 0');\n    }\n    if (offset < 0) {\n      throw ArgumentError.value(offset, 'offset', 'offset cannot be negative');\n    }\n  }\n\n  final QueryFilter where;\n  final List<QuerySort> sortBy;\n  final int? limit;\n  final int offset;\n}\n""",
)

# Dart wire format stays inside the existing opaque query payload.
replace_once(
    "lib/src/box.dart",
    """Map<String, dynamic> _queryWire(BoxQuery query) => <String, dynamic>{\n      'where': _filterWire(query.where),\n      'limit': query.limit,\n      'offset': query.offset,\n    };\n""",
    """Map<String, dynamic> _queryWire(BoxQuery query) => <String, dynamic>{\n      'where': _filterWire(query.where),\n      'sortBy': query.sortBy.map(_sortWire).toList(growable: false),\n      'limit': query.limit,\n      'offset': query.offset,\n    };\n\nMap<String, dynamic> _sortWire(QuerySort sort) => <String, dynamic>{\n      'field': sort.field,\n      'direction': sort.direction.name,\n      'nulls': sort.nulls.name,\n    };\n""",
)

# Dart contract tests.
replace_once(
    "test/query_test.dart",
    """      expect(\n        (query.where as QueryGroup).operator,\n        QueryLogicalOperator.and,\n      );\n    });\n\n    test('between requires an upper value', () {\n""",
    """      expect(\n        (query.where as QueryGroup).operator,\n        QueryLogicalOperator.and,\n      );\n    });\n\n    test('supports ordered sort clauses with explicit null placement', () {\n      final query = BoxQuery(\n        where: QueryComparison(\n          field: 'status',\n          operator: QueryOperator.equal,\n          value: 'active',\n        ),\n        sortBy: <QuerySort>[\n          QuerySort(\n            field: 'profile.age',\n            direction: QuerySortDirection.descending,\n            nulls: QueryNullOrder.first,\n          ),\n          QuerySort(field: 'name'),\n        ],\n      );\n\n      expect(query.sortBy, hasLength(2));\n      expect(query.sortBy.first.field, 'profile.age');\n      expect(query.sortBy.first.direction, QuerySortDirection.descending);\n      expect(query.sortBy.first.nulls, QueryNullOrder.first);\n      expect(query.sortBy.last.direction, QuerySortDirection.ascending);\n      expect(query.sortBy.last.nulls, QueryNullOrder.last);\n      expect(() => query.sortBy.add(QuerySort(field: 'id')), throwsUnsupportedError);\n    });\n\n    test('rejects malformed sort field paths', () {\n      expect(() => QuerySort(field: 'profile..age'), throwsArgumentError);\n    });\n\n    test('between requires an upper value', () {\n""",
)

# Rust query model and sorting support.
replace_once(
    "rust/src/query.rs",
    """pub struct QuerySpec {\n    pub filter: Filter,\n    pub limit: Option<usize>,\n    pub offset: usize,\n}\n""",
    """pub struct QuerySpec {\n    pub filter: Filter,\n    pub sort_by: Vec<SortSpec>,\n    pub limit: Option<usize>,\n    pub offset: usize,\n}\n""",
)
replace_once(
    "rust/src/query.rs",
    """pub enum CompareOp {\n    Equal,\n    NotEqual,\n    GreaterThan,\n    GreaterThanOrEqual,\n    LessThan,\n    LessThanOrEqual,\n    Between,\n    IsNull,\n    IsNotNull,\n}\n\n#[derive(Debug, Clone, Copy)]\nenum NumericValue {\n""",
    """pub enum CompareOp {\n    Equal,\n    NotEqual,\n    GreaterThan,\n    GreaterThanOrEqual,\n    LessThan,\n    LessThanOrEqual,\n    Between,\n    IsNull,\n    IsNotNull,\n}\n\n#[derive(Debug, Clone)]\npub struct SortSpec {\n    pub field: String,\n    pub direction: SortDirection,\n    pub nulls: NullOrder,\n}\n\n#[derive(Debug, Clone, Copy)]\npub enum SortDirection {\n    Ascending,\n    Descending,\n}\n\n#[derive(Debug, Clone, Copy)]\npub enum NullOrder {\n    First,\n    Last,\n}\n\n#[derive(Debug, Clone, Copy)]\npub(crate) enum NumericValue {\n""",
)
replace_once(
    "rust/src/query.rs",
    """    let filter = parse_filter(required(map, \"where\")?)?;\n    let limit = optional(map, \"limit\").map(as_usize).transpose()?.flatten();\n""",
    """    let filter = parse_filter(required(map, \"where\")?)?;\n    let sort_by = match optional(map, \"sortBy\") {\n        None => Vec::new(),\n        Some(value) if value.is_nil() => Vec::new(),\n        Some(value) => value\n            .as_array()\n            .ok_or_else(|| \"query sortBy must be a list\".to_string())?\n            .iter()\n            .map(parse_sort)\n            .collect::<Result<Vec<_>, _>>()?,\n    };\n    let limit = optional(map, \"limit\").map(as_usize).transpose()?.flatten();\n""",
)
replace_once(
    "rust/src/query.rs",
    """    Ok(QuerySpec {\n        filter,\n        limit,\n        offset,\n    })\n}\n\npub fn matches_record(payload: &[u8], filter: &Filter) -> Result<bool, String> {\n""",
    """    Ok(QuerySpec {\n        filter,\n        sort_by,\n        limit,\n        offset,\n    })\n}\n\npub fn matches_record(payload: &[u8], filter: &Filter) -> Result<bool, String> {\n""",
)
replace_once(
    "rust/src/query.rs",
    """pub fn matches_record(payload: &[u8], filter: &Filter) -> Result<bool, String> {\n    let record = decode_dxtr(payload)?;\n    matches_filter(&record, filter)\n}\n\npub fn validate_index_definition(name: &str, field: &str) -> Result<(), String> {\n""",
    """pub fn matches_record(payload: &[u8], filter: &Filter) -> Result<bool, String> {\n    let record = decode_dxtr(payload)?;\n    matches_filter(&record, filter)\n}\n\n#[derive(Debug, Clone)]\npub(crate) enum SortValue {\n    Nullish,\n    Numeric(NumericValue),\n    Text(String),\n}\n\n#[derive(Debug, Clone, Copy, PartialEq, Eq)]\nenum SortKind {\n    Numeric,\n    Text,\n}\n\npub(crate) fn sort_values(payload: &[u8], sorts: &[SortSpec]) -> Result<Vec<SortValue>, String> {\n    let record = decode_dxtr(payload)?;\n    sorts\n        .iter()\n        .map(|sort| {\n            let Some(value) = lookup_field(&record, &sort.field) else {\n                return Ok(SortValue::Nullish);\n            };\n            if value.is_nil() {\n                return Ok(SortValue::Nullish);\n            }\n            if let Some(number) = as_numeric(value) {\n                if matches!(number, NumericValue::Float(value) if value.is_nan()) {\n                    return Err(format!(\"sort field '{}' contains NaN, which is not orderable\", sort.field));\n                }\n                return Ok(SortValue::Numeric(number));\n            }\n            if let Some(value) = value.as_str() {\n                return Ok(SortValue::Text(value.to_string()));\n            }\n            Err(format!(\n                \"sort field '{}' contains a non-null value unsupported by ordered sorting\",\n                sort.field\n            ))\n        })\n        .collect()\n}\n\npub(crate) fn validate_sort_rows(\n    rows: &[Vec<SortValue>],\n    sorts: &[SortSpec],\n) -> Result<(), String> {\n    for (column, sort) in sorts.iter().enumerate() {\n        let mut kind = None;\n        for row in rows {\n            let current = match row.get(column) {\n                Some(SortValue::Nullish) => continue,\n                Some(SortValue::Numeric(_)) => SortKind::Numeric,\n                Some(SortValue::Text(_)) => SortKind::Text,\n                None => return Err(\"sort row width does not match sort specification\".to_string()),\n            };\n            match kind {\n                None => kind = Some(current),\n                Some(existing) if existing == current => {}\n                Some(_) => {\n                    return Err(format!(\n                        \"sort field '{}' mixes incompatible non-null ordered types\",\n                        sort.field\n                    ));\n                }\n            }\n        }\n    }\n    Ok(())\n}\n\npub(crate) fn compare_sort_rows(\n    left: &[SortValue],\n    left_key: &str,\n    right: &[SortValue],\n    right_key: &str,\n    sorts: &[SortSpec],\n) -> Ordering {\n    for (column, sort) in sorts.iter().enumerate() {\n        let Some(left_value) = left.get(column) else {\n            continue;\n        };\n        let Some(right_value) = right.get(column) else {\n            continue;\n        };\n        let ordering = match (left_value, right_value) {\n            (SortValue::Nullish, SortValue::Nullish) => Ordering::Equal,\n            (SortValue::Nullish, _) => match sort.nulls {\n                NullOrder::First => Ordering::Less,\n                NullOrder::Last => Ordering::Greater,\n            },\n            (_, SortValue::Nullish) => match sort.nulls {\n                NullOrder::First => Ordering::Greater,\n                NullOrder::Last => Ordering::Less,\n            },\n            (SortValue::Numeric(left), SortValue::Numeric(right)) => {\n                compare_numeric(*left, *right).unwrap_or(Ordering::Equal)\n            }\n            (SortValue::Text(left), SortValue::Text(right)) => left.cmp(right),\n            _ => Ordering::Equal,\n        };\n        if ordering != Ordering::Equal {\n            return match (left_value, right_value) {\n                (SortValue::Nullish, _) | (_, SortValue::Nullish) => ordering,\n                _ => match sort.direction {\n                    SortDirection::Ascending => ordering,\n                    SortDirection::Descending => ordering.reverse(),\n                },\n            };\n        }\n    }\n    left_key.cmp(right_key)\n}\n\npub fn validate_index_definition(name: &str, field: &str) -> Result<(), String> {\n""",
)
replace_once(
    "rust/src/query.rs",
    """fn parse_filter(value: &Value) -> Result<Filter, String> {\n""",
    """fn parse_sort(value: &Value) -> Result<SortSpec, String> {\n    let map = as_map(value)?;\n    let field = as_str(required(map, \"field\")?)?.to_string();\n    validate_field(&field)?;\n    let direction = match as_str(required(map, \"direction\")?)? {\n        \"ascending\" => SortDirection::Ascending,\n        \"descending\" => SortDirection::Descending,\n        other => return Err(format!(\"unsupported sort direction '{other}'\")),\n    };\n    let nulls = match as_str(required(map, \"nulls\")?)? {\n        \"first\" => NullOrder::First,\n        \"last\" => NullOrder::Last,\n        other => return Err(format!(\"unsupported sort null placement '{other}'\")),\n    };\n    Ok(SortSpec {\n        field,\n        direction,\n        nulls,\n    })\n}\n\nfn parse_filter(value: &Value) -> Result<Filter, String> {\n""",
)

# Native execution: sorted queries must filter all matches, sort, then paginate.
old_scan = """        keys.sort();\n        keys.dedup();\n        let mut matched = 0usize;\n        let mut results = Vec::new();\n        for key in keys {\n            let Some(value) = db::query_get(&read, &encryption, &key)? else {\n                continue;\n            };\n            if !query::matches_record(&value, &spec.filter)? {\n                continue;\n            }\n            if matched < spec.offset {\n                matched += 1;\n                continue;\n            }\n            results.push(NativeQueryRecord { key, value });\n            matched += 1;\n            if spec.limit.is_some_and(|limit| results.len() >= limit) {\n                break;\n            }\n        }\n        Ok(results)\n"""
new_scan = """        keys.sort();\n        keys.dedup();\n\n        if spec.sort_by.is_empty() {\n            let mut matched = 0usize;\n            let mut results = Vec::new();\n            for key in keys {\n                let Some(value) = db::query_get(&read, &encryption, &key)? else {\n                    continue;\n                };\n                if !query::matches_record(&value, &spec.filter)? {\n                    continue;\n                }\n                if matched < spec.offset {\n                    matched += 1;\n                    continue;\n                }\n                results.push(NativeQueryRecord { key, value });\n                matched += 1;\n                if spec.limit.is_some_and(|limit| results.len() >= limit) {\n                    break;\n                }\n            }\n            return Ok(results);\n        }\n\n        let mut sortable = Vec::new();\n        for key in keys {\n            let Some(value) = db::query_get(&read, &encryption, &key)? else {\n                continue;\n            };\n            if !query::matches_record(&value, &spec.filter)? {\n                continue;\n            }\n            let sort_values = query::sort_values(&value, &spec.sort_by)?;\n            sortable.push((key, value, sort_values));\n        }\n\n        let sort_rows = sortable\n            .iter()\n            .map(|(_, _, values)| values.clone())\n            .collect::<Vec<_>>();\n        query::validate_sort_rows(&sort_rows, &spec.sort_by)?;\n        sortable.sort_by(|left, right| {\n            query::compare_sort_rows(&left.2, &left.0, &right.2, &right.0, &spec.sort_by)\n        });\n\n        let limit = spec.limit.unwrap_or(usize::MAX);\n        Ok(sortable\n            .into_iter()\n            .skip(spec.offset)\n            .take(limit)\n            .map(|(key, value, _)| NativeQueryRecord { key, value })\n            .collect())\n"""
replace_once("rust/src/api.rs", old_scan, new_scan)

# Rust integration helpers and end-to-end coverage.
insert_before = """#[test]\nfn query_payload_is_valid_messagepack() {\n"""
sort_tests = r'''fn sorted_query_payload(
    filter_field: &str,
    filter_operator: &str,
    filter_value: Value,
    sort_field: &str,
    direction: &str,
    nulls: &str,
    limit: Option<u64>,
    offset: u64,
) -> Vec<u8> {
    let comparison = dxtr_map(vec![
        ("type", Value::from("comparison")),
        ("field", Value::from(filter_field)),
        ("operator", Value::from(filter_operator)),
        ("value", filter_value),
        ("upperValue", Value::Nil),
    ]);
    let sort = dxtr_map(vec![
        ("field", Value::from(sort_field)),
        ("direction", Value::from(direction)),
        ("nulls", Value::from(nulls)),
    ]);
    encode(&dxtr_map(vec![
        ("where", comparison),
        ("sortBy", Value::Array(vec![sort])),
        (
            "limit",
            limit.map(Value::from).unwrap_or(Value::Nil),
        ),
        ("offset", Value::from(offset)),
    ]))
}

#[test]
fn explicit_sort_orders_before_pagination_and_matches_index_execution() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("sorted".to_string(), None).unwrap();

    for (key, age) in [("a", 22), ("b", 40), ("c", 22), ("d", 17)] {
        put("sorted".to_string(), key.to_string(), person("active", age)).unwrap();
    }

    let payload = sorted_query_payload(
        "profile.age",
        "greaterThanOrEqual",
        Value::from(0_i64),
        "profile.age",
        "descending",
        "last",
        Some(2),
        1,
    );
    let scan = result_keys("sorted", payload.clone());
    assert_eq!(scan, vec!["a", "c"]);

    create_index(
        "sorted".to_string(),
        "by-age".to_string(),
        "profile.age".to_string(),
    )
    .unwrap();
    let indexed = result_keys("sorted", payload);
    assert_eq!(indexed, scan);

    close_box("sorted".to_string()).unwrap();
}

#[test]
fn explicit_sort_treats_missing_and_null_as_one_nullish_category() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("null_sort".to_string(), None).unwrap();

    put("null_sort".to_string(), "a".to_string(), person("active", 22)).unwrap();
    put(
        "null_sort".to_string(),
        "b".to_string(),
        encode(&dxtr_map(vec![
            ("status", Value::from("active")),
            ("profile", dxtr_map(vec![("age", Value::Nil)])),
        ])),
    )
    .unwrap();
    put(
        "null_sort".to_string(),
        "c".to_string(),
        encode(&dxtr_map(vec![("status", Value::from("active"))])),
    )
    .unwrap();
    put("null_sort".to_string(), "d".to_string(), person("active", 40)).unwrap();

    let payload = sorted_query_payload(
        "status",
        "isNotNull",
        Value::Nil,
        "profile.age",
        "ascending",
        "first",
        None,
        0,
    );
    assert_eq!(result_keys("null_sort", payload), vec!["b", "c", "a", "d"]);

    close_box("null_sort".to_string()).unwrap();
}

#[test]
fn explicit_sort_rejects_mixed_non_null_ordered_types() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("mixed_sort".to_string(), None).unwrap();

    put("mixed_sort".to_string(), "a".to_string(), person("active", 22)).unwrap();
    put(
        "mixed_sort".to_string(),
        "b".to_string(),
        encode(&dxtr_map(vec![
            ("status", Value::from("active")),
            ("profile", dxtr_map(vec![("age", Value::from("22"))])),
        ])),
    )
    .unwrap();

    let payload = sorted_query_payload(
        "status",
        "isNotNull",
        Value::Nil,
        "profile.age",
        "ascending",
        "last",
        None,
        0,
    );
    let error = scan_query("mixed_sort".to_string(), payload).unwrap_err();
    assert!(error.contains("mixes incompatible"));

    close_box("mixed_sort".to_string()).unwrap();
}

#[test]
fn explicit_sort_preserves_large_integer_precision() {
    let _guard = TEST_LOCK.lock().unwrap();
    let dir = tempfile::tempdir().unwrap();
    init_db(dir.path().to_string_lossy().to_string()).unwrap();
    open_box("precise_sort".to_string(), None).unwrap();

    put(
        "precise_sort".to_string(),
        "higher".to_string(),
        person("active", 9_007_199_254_740_993_i64),
    )
    .unwrap();
    put(
        "precise_sort".to_string(),
        "lower".to_string(),
        person("active", 9_007_199_254_740_992_i64),
    )
    .unwrap();

    let payload = sorted_query_payload(
        "status",
        "isNotNull",
        Value::Nil,
        "profile.age",
        "ascending",
        "last",
        None,
        0,
    );
    assert_eq!(
        result_keys("precise_sort", payload),
        vec!["lower", "higher"]
    );

    close_box("precise_sort".to_string()).unwrap();
}

'''
replace_once("rust/tests/query_index.rs", insert_before, sort_tests + insert_before)

# Makefile target keeps the new public query behavior easy to validate locally.
replace_once(
    "Makefile",
    ".PHONY: help pub-get format format-check analyze test rust-fmt rust-clippy rust-test rust-test-profiles rust-check frb-generate native-build native-build-minimal native-build-encryption native-size-baseline native-size-stability native-test query-index-test process-crash benchmark-smoke benchmark-full preflight example-android example-linux example-windows example-macos example-ios",
    ".PHONY: help pub-get format format-check analyze test rust-fmt rust-clippy rust-test rust-test-profiles rust-check frb-generate native-build native-build-minimal native-build-encryption native-size-baseline native-size-stability native-test query-index-test query-sort-test process-crash benchmark-smoke benchmark-full preflight example-android example-linux example-windows example-macos example-ios",
)
replace_once(
    "Makefile",
    "\t@echo \"  make query-index-test     Rust full-profile query/index integration test\"\n",
    "\t@echo \"  make query-index-test     Rust full-profile query/index integration test\"\n\t@echo \"  make query-sort-test      Dart sort contract + Rust query sort integration tests\"\n",
)
replace_once(
    "Makefile",
    """query-index-test:\n\t$(CARGO) test --manifest-path rust/Cargo.toml --test query_index -- --nocapture\n\nprocess-crash:\n""",
    """query-index-test:\n\t$(CARGO) test --manifest-path rust/Cargo.toml --test query_index -- --nocapture\n\nquery-sort-test: pub-get\n\t$(FLUTTER) test test/query_test.dart\n\t$(CARGO) test --manifest-path rust/Cargo.toml --test query_index explicit_sort -- --nocapture\n\nprocess-crash:\n""",
)
