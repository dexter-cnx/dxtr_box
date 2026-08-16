from pathlib import Path

path = Path("rust/tests/query_index.rs")
text = path.read_text()
old = '''fn sorted_query_payload(
    filter_field: &str,
    filter_operator: &str,
    filter_value: Value,
    sort_field: &str,
    direction: &str,
    nulls: &str,
    limit: Option<u64>,
    offset: u64,
) -> Vec<u8> {
'''
new = '''fn sorted_query_payload(
    filter: (&str, &str, Value),
    sort: (&str, &str, &str),
    limit: Option<u64>,
    offset: u64,
) -> Vec<u8> {
    let (filter_field, filter_operator, filter_value) = filter;
    let (sort_field, direction, nulls) = sort;
'''
if old not in text:
    raise SystemExit("sorted_query_payload signature anchor not found")
text = text.replace(old, new, 1)

replacements = {
'''sorted_query_payload(
        "profile.age",
        "greaterThanOrEqual",
        Value::from(0_i64),
        "profile.age",
        "descending",
        "last",
        Some(2),
        1,
    )''': '''sorted_query_payload(
        ("profile.age", "greaterThanOrEqual", Value::from(0_i64)),
        ("profile.age", "descending", "last"),
        Some(2),
        1,
    )''',
'''sorted_query_payload(
        "status",
        "isNotNull",
        Value::Nil,
        "profile.age",
        "ascending",
        "first",
        None,
        0,
    )''': '''sorted_query_payload(
        ("status", "isNotNull", Value::Nil),
        ("profile.age", "ascending", "first"),
        None,
        0,
    )''',
'''sorted_query_payload(
        "status",
        "isNotNull",
        Value::Nil,
        "profile.age",
        "ascending",
        "last",
        None,
        0,
    )''': '''sorted_query_payload(
        ("status", "isNotNull", Value::Nil),
        ("profile.age", "ascending", "last"),
        None,
        0,
    )''',
}
for old_call, new_call in replacements.items():
    if old_call not in text:
        raise SystemExit(f"query sort call anchor not found: {old_call.splitlines()[1].strip()}")
    text = text.replace(old_call, new_call)

path.write_text(text)
