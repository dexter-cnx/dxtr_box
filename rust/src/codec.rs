use serde::de::IgnoredAny;

/// Validate that payload is syntactically valid MessagePack before persisting it.
/// Dart owns public dynamic type adaptation; Rust owns durable bytes.
pub fn validate_message_pack(bytes: &[u8]) -> Result<(), String> {
    let _: IgnoredAny =
        rmp_serde::from_slice(bytes).map_err(|e| format!("invalid MessagePack: {e}"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_message_pack() {
        let bytes = rmp_serde::to_vec(&vec!["@dxtr:list", "payload"]).unwrap();
        assert!(validate_message_pack(&bytes).is_ok());
    }

    #[test]
    fn rejects_garbage() {
        assert!(validate_message_pack(&[0xc1]).is_err());
    }
}
