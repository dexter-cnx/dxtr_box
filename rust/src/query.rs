use std::cmp::Ordering;
use std::io::Cursor;

use rmpv::Value;

#[derive(Debug, Clone)]
pub struct QuerySpec {
    pub filter: Filter,
    pub limit: Option<usize>,
    pub offset: usize,
}

#[derive(Debug, Clone)]
pub enum Filter {
    Comparison(Comparison),
    Group { op: LogicalOp, filters: Vec<Filter> },
}

#[derive(Debug, Clone)]
pub struct Comparison {
    pub field: String,
    pub op: CompareOp,
    pub value: Option<Value>,
    pub upper_value: Option<Value>,
}

#[derive(Debug, Clone, Copy)]
pub enum LogicalOp {
    And,
    Or,
}

#[derive(Debug, Clone, Copy)]
pub enum CompareOp {
    Equal,
    NotEqual,
    GreaterThan,
    GreaterThanOrEqual,
    LessThan,
    LessThanOrEqual,
    Between,
    IsNull,
    IsNotNull,
}

#[derive(Debug, Clone, Copy)]
enum NumericValue {
    Signed(i64),
    Unsigned(u64),
    Float(f64),
}

pub fn decode_query(bytes: &[u8]) -> Result<QuerySpec, String> {
    let value = decode_dxtr(bytes)?;
    let map = as_map(&value)?;
    let filter = parse_filter(required(map, "where")?)?;
    let limit = optional(map, "limit").map(as_usize).transpose()?.flatten();
    let offset = optional(map, "offset")
        .map(as_usize)
        .transpose()?
        .flatten()
        .unwrap_or(0);
    if matches!(limit, Some(0)) {
        return Err("query limit must be greater than 0".to_string());
    }
    Ok(QuerySpec {
        filter,
        limit,
        offset,
    })
}

pub fn matches_record(payload: &[u8], filter: &Filter) -> Result<bool, String> {
    let record = decode_dxtr(payload)?;
    matches_filter(&record, filter)
}

pub fn validate_index_definition(name: &str, field: &str) -> Result<(), String> {
    let mut chars = name.chars();
    match chars.next() {
        Some(first) if first.is_ascii_alphabetic() => {}
        _ => return Err("index name must start with a letter".to_string()),
    }
    if !name
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '_' || ch == '-')
    {
        return Err("index name may contain only letters, digits, _ or -".to_string());
    }
    validate_field(field)
}

pub fn index_scalar_key(payload: &[u8], field: &str) -> Result<Option<Vec<u8>>, String> {
    let record = decode_dxtr(payload)?;
    let Some(value) = lookup_field(&record, field) else {
        return Ok(None);
    };
    if !is_index_scalar(value) {
        return Err(format!(
            "field '{field}' contains a value unsupported by scalar indexes"
        ));
    }
    let mut encoded = Vec::new();
    rmpv::encode::write_value(&mut encoded, value).map_err(|e| e.to_string())?;
    Ok(Some(encoded))
}

fn parse_filter(value: &Value) -> Result<Filter, String> {
    let map = as_map(value)?;
    match as_str(required(map, "type")?)? {
        "comparison" => {
            let field = as_str(required(map, "field")?)?.to_string();
            validate_field(&field)?;
            let op = match as_str(required(map, "operator")?)? {
                "equal" => CompareOp::Equal,
                "notEqual" => CompareOp::NotEqual,
                "greaterThan" => CompareOp::GreaterThan,
                "greaterThanOrEqual" => CompareOp::GreaterThanOrEqual,
                "lessThan" => CompareOp::LessThan,
                "lessThanOrEqual" => CompareOp::LessThanOrEqual,
                "between" => CompareOp::Between,
                "isNull" => CompareOp::IsNull,
                "isNotNull" => CompareOp::IsNotNull,
                other => return Err(format!("unsupported query operator '{other}'")),
            };
            let comparison = Comparison {
                field,
                op,
                value: optional(map, "value").cloned(),
                upper_value: optional(map, "upperValue").cloned(),
            };
            if matches!(comparison.op, CompareOp::Between) && comparison.upper_value.is_none() {
                return Err("between requires upperValue".to_string());
            }
            Ok(Filter::Comparison(comparison))
        }
        "group" => {
            let op = match as_str(required(map, "operator")?)? {
                "and" => LogicalOp::And,
                "or" => LogicalOp::Or,
                other => return Err(format!("unsupported logical operator '{other}'")),
            };
            let values = required(map, "filters")?
                .as_array()
                .ok_or_else(|| "query group filters must be a list".to_string())?;
            if values.is_empty() {
                return Err("query group requires at least one filter".to_string());
            }
            let filters = values
                .iter()
                .map(parse_filter)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(Filter::Group { op, filters })
        }
        other => Err(format!("unsupported query filter type '{other}'")),
    }
}

fn matches_filter(record: &Value, filter: &Filter) -> Result<bool, String> {
    match filter {
        Filter::Comparison(comparison) => matches_comparison(record, comparison),
        Filter::Group { op, filters } => match op {
            LogicalOp::And => {
                for filter in filters {
                    if !matches_filter(record, filter)? {
                        return Ok(false);
                    }
                }
                Ok(true)
            }
            LogicalOp::Or => {
                for filter in filters {
                    if matches_filter(record, filter)? {
                        return Ok(true);
                    }
                }
                Ok(false)
            }
        },
    }
}

fn matches_comparison(record: &Value, comparison: &Comparison) -> Result<bool, String> {
    let Some(actual) = lookup_field(record, &comparison.field) else {
        return Ok(false);
    };
    let result = match comparison.op {
        CompareOp::IsNull => actual.is_nil(),
        CompareOp::IsNotNull => !actual.is_nil(),
        CompareOp::Equal => comparison
            .value
            .as_ref()
            .is_some_and(|value| values_equal(actual, value)),
        CompareOp::NotEqual => comparison
            .value
            .as_ref()
            .is_some_and(|value| !values_equal(actual, value)),
        CompareOp::GreaterThan => {
            compare(actual, comparison.value.as_ref())? == Some(Ordering::Greater)
        }
        CompareOp::GreaterThanOrEqual => matches!(
            compare(actual, comparison.value.as_ref())?,
            Some(Ordering::Greater | Ordering::Equal)
        ),
        CompareOp::LessThan => compare(actual, comparison.value.as_ref())? == Some(Ordering::Less),
        CompareOp::LessThanOrEqual => matches!(
            compare(actual, comparison.value.as_ref())?,
            Some(Ordering::Less | Ordering::Equal)
        ),
        CompareOp::Between => {
            let lower = compare(actual, comparison.value.as_ref())?;
            let upper = compare(actual, comparison.upper_value.as_ref())?;
            matches!(lower, Some(Ordering::Greater | Ordering::Equal))
                && matches!(upper, Some(Ordering::Less | Ordering::Equal))
        }
    };
    Ok(result)
}

fn compare(actual: &Value, expected: Option<&Value>) -> Result<Option<Ordering>, String> {
    let Some(expected) = expected else {
        return Ok(None);
    };
    if let (Some(left), Some(right)) = (as_numeric(actual), as_numeric(expected)) {
        return Ok(compare_numeric(left, right));
    }
    if let (Some(left), Some(right)) = (actual.as_str(), expected.as_str()) {
        return Ok(Some(left.cmp(right)));
    }
    Err("ordered query comparisons support only numbers and strings".to_string())
}

fn values_equal(left: &Value, right: &Value) -> bool {
    if let (Some(left), Some(right)) = (as_numeric(left), as_numeric(right)) {
        return compare_numeric(left, right) == Some(Ordering::Equal);
    }
    left == right
}

fn as_numeric(value: &Value) -> Option<NumericValue> {
    if let Some(value) = value.as_i64() {
        return Some(NumericValue::Signed(value));
    }
    if let Some(value) = value.as_u64() {
        return Some(NumericValue::Unsigned(value));
    }
    value.as_f64().map(NumericValue::Float)
}

fn compare_numeric(left: NumericValue, right: NumericValue) -> Option<Ordering> {
    match (left, right) {
        (NumericValue::Signed(left), NumericValue::Signed(right)) => Some(left.cmp(&right)),
        (NumericValue::Unsigned(left), NumericValue::Unsigned(right)) => Some(left.cmp(&right)),
        (NumericValue::Signed(left), NumericValue::Unsigned(right)) => {
            if left < 0 {
                Some(Ordering::Less)
            } else {
                Some((left as u64).cmp(&right))
            }
        }
        (NumericValue::Unsigned(left), NumericValue::Signed(right)) => {
            compare_numeric(NumericValue::Signed(right), NumericValue::Unsigned(left))
                .map(Ordering::reverse)
        }
        (NumericValue::Float(left), NumericValue::Float(right)) => left.partial_cmp(&right),
        (NumericValue::Signed(left), NumericValue::Float(right)) => compare_i64_f64(left, right),
        (NumericValue::Float(left), NumericValue::Signed(right)) => {
            compare_i64_f64(right, left).map(Ordering::reverse)
        }
        (NumericValue::Unsigned(left), NumericValue::Float(right)) => compare_u64_f64(left, right),
        (NumericValue::Float(left), NumericValue::Unsigned(right)) => {
            compare_u64_f64(right, left).map(Ordering::reverse)
        }
    }
}

fn compare_i64_f64(integer: i64, float: f64) -> Option<Ordering> {
    if float.is_nan() {
        return None;
    }
    if float == f64::NEG_INFINITY {
        return Some(Ordering::Greater);
    }
    if float == f64::INFINITY {
        return Some(Ordering::Less);
    }

    const TWO_POW_63: f64 = 9_223_372_036_854_775_808.0;
    if float >= TWO_POW_63 {
        return Some(Ordering::Less);
    }
    if float < -TWO_POW_63 {
        return Some(Ordering::Greater);
    }

    let truncated = float.trunc();
    let truncated_integer = truncated as i64;
    match integer.cmp(&truncated_integer) {
        Ordering::Equal if float == truncated => Some(Ordering::Equal),
        Ordering::Equal if float > truncated => Some(Ordering::Less),
        Ordering::Equal => Some(Ordering::Greater),
        ordering => Some(ordering),
    }
}

fn compare_u64_f64(integer: u64, float: f64) -> Option<Ordering> {
    if float.is_nan() {
        return None;
    }
    if float == f64::NEG_INFINITY || float < 0.0 {
        return Some(Ordering::Greater);
    }
    if float == f64::INFINITY {
        return Some(Ordering::Less);
    }

    const TWO_POW_64: f64 = 18_446_744_073_709_551_616.0;
    if float >= TWO_POW_64 {
        return Some(Ordering::Less);
    }

    let truncated = float.trunc();
    let truncated_integer = truncated as u64;
    match integer.cmp(&truncated_integer) {
        Ordering::Equal if float == truncated => Some(Ordering::Equal),
        Ordering::Equal if float > truncated => Some(Ordering::Less),
        Ordering::Equal => Some(Ordering::Greater),
        ordering => Some(ordering),
    }
}

fn lookup_field<'a>(record: &'a Value, path: &str) -> Option<&'a Value> {
    let mut current = record;
    for segment in path.split('.') {
        let map = current.as_map()?;
        current = map
            .iter()
            .find_map(|(key, value)| (key.as_str() == Some(segment)).then_some(value))?;
    }
    Some(current)
}

fn decode_dxtr(bytes: &[u8]) -> Result<Value, String> {
    let mut cursor = Cursor::new(bytes);
    let value = rmpv::decode::read_value(&mut cursor)
        .map_err(|e| format!("invalid MessagePack query payload: {e}"))?;
    normalize_dxtr(value)
}

fn normalize_dxtr(value: Value) -> Result<Value, String> {
    match value {
        Value::Array(values) if values.len() == 2 => {
            let tag = values[0].as_str().map(str::to_string);
            match tag.as_deref() {
                Some("@dxtr:map") => {
                    let pairs = values[1]
                        .as_array()
                        .ok_or_else(|| "invalid @dxtr:map payload".to_string())?;
                    let mut map = Vec::with_capacity(pairs.len());
                    for pair in pairs {
                        let pair = pair
                            .as_array()
                            .ok_or_else(|| "invalid @dxtr:map entry".to_string())?;
                        if pair.len() != 2 {
                            return Err("invalid @dxtr:map entry length".to_string());
                        }
                        let key = pair[0]
                            .as_str()
                            .ok_or_else(|| "dxtr map keys must be strings".to_string())?;
                        map.push((Value::from(key), normalize_dxtr(pair[1].clone())?));
                    }
                    Ok(Value::Map(map))
                }
                Some("@dxtr:list") => {
                    let items = values[1]
                        .as_array()
                        .ok_or_else(|| "invalid @dxtr:list payload".to_string())?;
                    Ok(Value::Array(
                        items
                            .iter()
                            .cloned()
                            .map(normalize_dxtr)
                            .collect::<Result<Vec<_>, _>>()?,
                    ))
                }
                _ => Ok(Value::Array(
                    values
                        .into_iter()
                        .map(normalize_dxtr)
                        .collect::<Result<Vec<_>, _>>()?,
                )),
            }
        }
        Value::Array(values) => Ok(Value::Array(
            values
                .into_iter()
                .map(normalize_dxtr)
                .collect::<Result<Vec<_>, _>>()?,
        )),
        Value::Map(entries) => Ok(Value::Map(
            entries
                .into_iter()
                .map(|(key, value)| Ok((normalize_dxtr(key)?, normalize_dxtr(value)?)))
                .collect::<Result<Vec<_>, String>>()?,
        )),
        other => Ok(other),
    }
}

fn as_map(value: &Value) -> Result<&[(Value, Value)], String> {
    value
        .as_map()
        .map(Vec::as_slice)
        .ok_or_else(|| "query payload must be a map".to_string())
}

fn required<'a>(map: &'a [(Value, Value)], key: &str) -> Result<&'a Value, String> {
    optional(map, key).ok_or_else(|| format!("query payload is missing '{key}'"))
}

fn optional<'a>(map: &'a [(Value, Value)], key: &str) -> Option<&'a Value> {
    map.iter()
        .find_map(|(candidate, value)| (candidate.as_str() == Some(key)).then_some(value))
}

fn as_str(value: &Value) -> Result<&str, String> {
    value
        .as_str()
        .ok_or_else(|| "query field must be a string".to_string())
}

fn as_usize(value: &Value) -> Result<Option<usize>, String> {
    if value.is_nil() {
        return Ok(None);
    }
    let raw = value
        .as_u64()
        .ok_or_else(|| "query pagination values must be non-negative integers".to_string())?;
    usize::try_from(raw)
        .map(Some)
        .map_err(|_| "query pagination value is too large".to_string())
}

fn is_index_scalar(value: &Value) -> bool {
    value.is_nil()
        || value.is_bool()
        || value.as_i64().is_some()
        || value.as_u64().is_some()
        || value.as_f64().is_some()
        || value.as_str().is_some()
}

fn validate_field(field: &str) -> Result<(), String> {
    if field.is_empty()
        || field.starts_with('.')
        || field.ends_with('.')
        || field.split('.').any(str::is_empty)
    {
        return Err("field must be a non-empty dotted path".to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_invalid_dxtr_map_payload() {
        let payload = rmp_serde::to_vec(&vec!["@dxtr:map", "placeholder"]).unwrap();
        assert!(decode_dxtr(&payload).is_err());
    }

    #[test]
    fn integer_comparisons_preserve_values_above_f64_exact_range() {
        let lower = Value::from(9_007_199_254_740_992_i64);
        let higher = Value::from(9_007_199_254_740_993_i64);

        assert!(!values_equal(&lower, &higher));
        assert_eq!(compare(&higher, Some(&lower)).unwrap(), Some(Ordering::Greater));
        assert_eq!(compare(&lower, Some(&higher)).unwrap(), Some(Ordering::Less));
    }

    #[test]
    fn signed_and_unsigned_integer_comparisons_remain_exact() {
        let negative = Value::from(-1_i64);
        let zero = Value::from(0_u64);
        let max_signed = Value::from(i64::MAX);
        let above_signed = Value::from((i64::MAX as u64) + 1);

        assert_eq!(compare(&negative, Some(&zero)).unwrap(), Some(Ordering::Less));
        assert_eq!(
            compare(&above_signed, Some(&max_signed)).unwrap(),
            Some(Ordering::Greater)
        );
    }

    #[test]
    fn integer_float_comparisons_do_not_round_large_integers_to_float() {
        let integer = Value::from(9_007_199_254_740_993_i64);
        let rounded_float = Value::from(9_007_199_254_740_992_f64);

        assert!(!values_equal(&integer, &rounded_float));
        assert_eq!(
            compare(&integer, Some(&rounded_float)).unwrap(),
            Some(Ordering::Greater)
        );
    }
}
