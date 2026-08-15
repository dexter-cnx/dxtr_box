use argon2::Argon2;
use chacha20poly1305::{
    aead::{Aead, KeyInit, Payload},
    ChaCha20Poly1305, Nonce,
};
use rand_core::{OsRng, RngCore};

pub const SALT_LEN: usize = 16;
pub const NONCE_LEN: usize = 12;

pub fn new_salt() -> [u8; SALT_LEN] {
    let mut salt = [0u8; SALT_LEN];
    OsRng.fill_bytes(&mut salt);
    salt
}

pub fn derive_key(password: &str, salt: &[u8]) -> Result<[u8; 32], String> {
    let mut key = [0u8; 32];
    Argon2::default()
        .hash_password_into(password.as_bytes(), salt, &mut key)
        .map_err(|e| format!("argon2: {e}"))?;
    Ok(key)
}

pub fn encrypt(key: &[u8; 32], plaintext: &[u8]) -> Result<Vec<u8>, String> {
    encrypt_with_aad(key, &[], plaintext)
}

pub fn encrypt_with_aad(key: &[u8; 32], aad: &[u8], plaintext: &[u8]) -> Result<Vec<u8>, String> {
    let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|e| e.to_string())?;
    let mut nonce_bytes = [0u8; NONCE_LEN];
    OsRng.fill_bytes(&mut nonce_bytes);
    let ciphertext = cipher
        .encrypt(
            Nonce::from_slice(&nonce_bytes),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        .map_err(|e| format!("encrypt: {e}"))?;
    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

pub fn decrypt(key: &[u8; 32], payload: &[u8]) -> Result<Vec<u8>, String> {
    decrypt_with_aad(key, &[], payload)
}

pub fn decrypt_with_aad(key: &[u8; 32], aad: &[u8], payload: &[u8]) -> Result<Vec<u8>, String> {
    if payload.len() < NONCE_LEN {
        return Err("encrypted payload is truncated".into());
    }
    let (nonce, ciphertext) = payload.split_at(NONCE_LEN);
    let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|e| e.to_string())?;
    cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ciphertext,
                aad,
            },
        )
        .map_err(|e| format!("decrypt: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let salt = new_salt();
        let key = derive_key("secret", &salt).unwrap();
        let payload = encrypt(&key, b"dxtr").unwrap();
        assert_eq!(decrypt(&key, &payload).unwrap(), b"dxtr");
    }

    #[test]
    fn aad_round_trip_rejects_a_different_record_key() {
        let salt = new_salt();
        let key = derive_key("secret", &salt).unwrap();
        let payload = encrypt_with_aad(&key, b"record-a", b"dxtr").unwrap();

        assert_eq!(
            decrypt_with_aad(&key, b"record-a", &payload).unwrap(),
            b"dxtr"
        );
        assert!(decrypt_with_aad(&key, b"record-b", &payload).is_err());
    }

    #[test]
    fn wrong_key_and_tampering_are_rejected() {
        let salt = new_salt();
        let key = derive_key("secret", &salt).unwrap();
        let wrong_key = derive_key("wrong", &salt).unwrap();
        let mut payload = encrypt(&key, b"dxtr").unwrap();

        assert!(decrypt(&wrong_key, &payload).is_err());

        let last = payload.len() - 1;
        payload[last] ^= 0x01;
        assert!(decrypt(&key, &payload).is_err());
    }

    #[test]
    fn truncated_payload_is_rejected() {
        let key = [0u8; 32];
        assert!(decrypt(&key, &[0u8; NONCE_LEN - 1]).is_err());
    }
}
