#[cfg(feature = "encryption")]
mod enabled {
    use argon2::Argon2;
    use chacha20poly1305::{
        aead::{Aead, KeyInit},
        ChaCha20Poly1305, Nonce,
    };
    use rand_core::{OsRng, RngCore};

    const SALT_LEN: usize = 16;
    const NONCE_LEN: usize = 12;

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
        let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|e| e.to_string())?;
        let mut nonce_bytes = [0u8; NONCE_LEN];
        OsRng.fill_bytes(&mut nonce_bytes);
        let ciphertext = cipher
            .encrypt(Nonce::from_slice(&nonce_bytes), plaintext)
            .map_err(|e| format!("encrypt: {e}"))?;
        let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
        out.extend_from_slice(&nonce_bytes);
        out.extend_from_slice(&ciphertext);
        Ok(out)
    }

    pub fn decrypt(key: &[u8; 32], payload: &[u8]) -> Result<Vec<u8>, String> {
        if payload.len() < NONCE_LEN {
            return Err("encrypted payload is truncated".into());
        }
        let (nonce, ciphertext) = payload.split_at(NONCE_LEN);
        let cipher = ChaCha20Poly1305::new_from_slice(key).map_err(|e| e.to_string())?;
        cipher
            .decrypt(Nonce::from_slice(nonce), ciphertext)
            .map_err(|e| format!("decrypt: {e}"))
    }
}

#[cfg(feature = "encryption")]
pub use enabled::*;
