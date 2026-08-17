use std::io::Cursor;

use blake3::Hasher;
use rmpv::Value;

const INDEX_KEY_CONTEXT: &str = "dxtr_box 2026-08-17 encrypted equality index subkey v1";
const TOKEN_DOMAIN: &[u8] = b"dxtr_box:index-equality-token:v1";

pub(crate) fn encrypted_equality_token(
    master_key: &[u8; 32],
    index_name: &str,
    field: &str,
    scalar_messagepack: &[u8],
) -> Result<Vec<u8>, String> {
    let canonical = canonical_equality_scalar(scalar_messagepack)?;
    let index_key = blake3::derive_key(INDEX_KEY_CONTEXT, master_key);
    let mut hasher = Hasher::new_keyed(&index_key);
    update_component(&mut hasher, TOKEN_DOMAIN);
    update_component(&mut hasher, index_name.as_bytes());
    update_component(&mut hasher, field.as_bytes());
    update_component(&mut hasher, &canonical);
    Ok(hasher.finalize().as_bytes().to_vec())
}

fn canonical_equality_scalar(bytes: &[u8]) -> Result<Vec<u8>, String> {
    let mut cursor = Cursor::new(bytes);
    let value = rmpv::decode::read_value(&mut cursor)
        .map_err(|error| format!("invalid encrypted index scalar: {error}"))?;
    if cursor.position() != bytes.len() as u64 {
        return Err("invalid encrypted index scalar has trailing bytes".to_string());
    }

    let mut output = Vec::new();
    match value {
        Value::Nil => output.push(0x00),
        Value::Boolean(false) => output.push(0x01),
        Value::Boolean(true) => output.push(0x02),
        Value::Integer(integer) => {
            if let Some(value) = integer.as_i64() {
                push_integer(&mut output, value);
            } else if let Some(value) = integer.as_u64() {
                push_unsigned(&mut output, value);
            } else {
                return Err("encrypted index integer is outside supported range".to_string());
            }
        }
        Value::F32(value) => push_float(&mut output, value as f64),
        Value::F64(value) => push_float(&mut output, value),
        Value::String(value) => {
            let value = value
                .as_str()
                .ok_or_else(|| "encrypted index string is not valid UTF-8".to_string())?;
            output.push(0x20);
            output.extend_from_slice(value.as_bytes());
        }
        _ => return Err("encrypted equality indexes support scalar values only".to_string()),
    }
    Ok(output)
}

fn push_integer(output: &mut Vec<u8>, value: i64) {
    if value < 0 {
        output.push(0x10);
        output.extend_from_slice(&value.to_be_bytes());
    } else {
        push_unsigned(output, value as u64);
    }
}

fn push_unsigned(output: &mut Vec<u8>, value: u64) {
    output.push(0x11);
    output.extend_from_slice(&value.to_be_bytes());
}

fn push_float(output: &mut Vec<u8>, value: f64) {
    const TWO_POW_63: f64 = 9_223_372_036_854_775_808.0;
    const TWO_POW_64: f64 = 18_446_744_073_709_551_616.0;

    if value.is_finite() && value == value.trunc() {
        if (0.0..TWO_POW_64).contains(&value) {
            push_unsigned(output, value as u64);
            return;
        }
        if (-TWO_POW_63..0.0).contains(&value) {
            push_integer(output, value as i64);
            return;
        }
    }

    output.push(0x12);
    output.extend_from_slice(&value.to_bits().to_be_bytes());
}

fn update_component(hasher: &mut Hasher, value: &[u8]) {
    hasher.update(&(value.len() as u64).to_be_bytes());
    hasher.update(value);
}

#[cfg(test)]
mod tests {
    use super::*;

    fn encode(value: Value) -> Vec<u8> {
        let mut bytes = Vec::new();
        rmpv::encode::write_value(&mut bytes, &value).unwrap();
        bytes
    }

    #[test]
    fn token_is_deterministic_and_domain_separated() {
        let key = [0x42; 32];
        let scalar = encode(Value::from("active"));
        let first = encrypted_equality_token(&key, "by-status", "status", &scalar).unwrap();
        let repeated = encrypted_equality_token(&key, "by-status", "status", &scalar).unwrap();
        let other_index = encrypted_equality_token(&key, "by-status-2", "status", &scalar).unwrap();
        let other_field =
            encrypted_equality_token(&key, "by-status", "profile.status", &scalar).unwrap();

        assert_eq!(first, repeated);
        assert_eq!(first.len(), 32);
        assert_ne!(first, scalar);
        assert_ne!(first, other_index);
        assert_ne!(first, other_field);
    }

    #[test]
    fn numeric_tokens_follow_query_numeric_equality_semantics() {
        let key = [0x24; 32];
        let signed =
            encrypted_equality_token(&key, "by-value", "value", &encode(Value::from(42_i64)))
                .unwrap();
        let unsigned =
            encrypted_equality_token(&key, "by-value", "value", &encode(Value::from(42_u64)))
                .unwrap();
        let float =
            encrypted_equality_token(&key, "by-value", "value", &encode(Value::F64(42.0))).unwrap();
        let negative_zero =
            encrypted_equality_token(&key, "by-zero", "value", &encode(Value::F64(-0.0))).unwrap();
        let integer_zero =
            encrypted_equality_token(&key, "by-zero", "value", &encode(Value::from(0_u64)))
                .unwrap();

        assert_eq!(signed, unsigned);
        assert_eq!(signed, float);
        assert_eq!(negative_zero, integer_zero);
    }

    #[test]
    fn distinct_numeric_values_do_not_share_tokens() {
        let key = [0x11; 32];
        let lower = encrypted_equality_token(
            &key,
            "by-value",
            "value",
            &encode(Value::from(9_007_199_254_740_992_u64)),
        )
        .unwrap();
        let higher = encrypted_equality_token(
            &key,
            "by-value",
            "value",
            &encode(Value::from(9_007_199_254_740_993_u64)),
        )
        .unwrap();

        assert_ne!(lower, higher);
    }

    #[test]
    fn token_rejects_trailing_or_non_scalar_payloads() {
        let key = [0x10; 32];
        let mut trailing = encode(Value::from("active"));
        trailing.extend_from_slice(&encode(Value::from("extra")));
        assert!(encrypted_equality_token(&key, "by-status", "status", &trailing).is_err());

        let array = encode(Value::Array(vec![Value::from(1_i64)]));
        assert!(encrypted_equality_token(&key, "by-status", "status", &array).is_err());
    }
}
