from pathlib import Path
import re

path = Path('rust/src/db.rs')
text = path.read_text()

text, count = re.subn(
    r'    fn encode_value\(&self, plaintext: &\[u8\]\) -> Result<Vec<u8>, String> \{.*?\n    \}\n\n    fn decode_value\(&self, stored: &\[u8\]\) -> Result<Vec<u8>, String> \{.*?\n    \}\n',
    '''    fn encode_value(&self, record_key: &str, plaintext: &[u8]) -> Result<Vec<u8>, String> {
        match self {
            Self::Plain => Ok(plaintext.to_vec()),
            #[cfg(feature = "encryption")]
            Self::Encrypted { key, .. } => {
                crypto::encrypt_with_aad(key, record_key.as_bytes(), plaintext)
            }
        }
    }

    fn decode_value(&self, record_key: &str, stored: &[u8]) -> Result<Vec<u8>, String> {
        match self {
            Self::Plain => Ok(stored.to_vec()),
            #[cfg(feature = "encryption")]
            Self::Encrypted { key, .. } => {
                crypto::decrypt_with_aad(key, record_key.as_bytes(), stored)
                    .map_err(|_| "encrypted value authentication failed".to_string())
            }
        }
    }
''',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'encode/decode replacement count={count}')

text, count = re.subn(
    r'#\[cfg\(feature = "encryption"\)\]\nfn write_encrypted_metadata\(.*?\nfn resolve_existing_box\(',
    '''fn initialize_new_box(
    db: &Database,
    encryption_key: Option<&str>,
) -> Result<EncryptionState, String> {
    match encryption_key {
        None => {
            let write = db.begin_write().map_err(|e| e.to_string())?;
            {
                write.open_table(DATA).map_err(|e| e.to_string())?;
                let mut meta = write.open_table(META).map_err(|e| e.to_string())?;
                meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                    .map_err(|e| e.to_string())?;
                meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_NONE)
                    .map_err(|e| e.to_string())?;
            }
            write.commit().map_err(|e| e.to_string())?;
            Ok(EncryptionState::Plain)
        }
        Some(password) => {
            if password.is_empty() {
                return Err("encryption key cannot be empty".to_string());
            }
            #[cfg(feature = "encryption")]
            {
                let salt = crypto::new_salt();
                let key = crypto::derive_key(password, &salt)?;
                let key_check = crypto::encrypt(&key, KEY_CHECK_PLAINTEXT)?;
                let write = db.begin_write().map_err(|e| e.to_string())?;
                {
                    write.open_table(DATA).map_err(|e| e.to_string())?;
                    let mut meta = write.open_table(META).map_err(|e| e.to_string())?;
                    meta.insert(META_FORMAT_VERSION, FORMAT_VERSION)
                        .map_err(|e| e.to_string())?;
                    meta.insert(META_ENCRYPTION_MODE, ENCRYPTION_CHACHA20POLY1305)
                        .map_err(|e| e.to_string())?;
                    meta.insert(META_ENCRYPTION_SALT, salt.as_slice())
                        .map_err(|e| e.to_string())?;
                    meta.insert(META_KEY_CHECK, key_check.as_slice())
                        .map_err(|e| e.to_string())?;
                }
                write.commit().map_err(|e| e.to_string())?;
                Ok(EncryptionState::Encrypted { key, salt })
            }
            #[cfg(not(feature = "encryption"))]
            {
                let _ = password;
                Err("this native build was compiled without encryption support".to_string())
            }
        }
    }
}

fn resolve_existing_box(''',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'initializer replacement count={count}')

text, count = re.subn(
    r'    let db = Arc::new\(Database::create\(&path\)\.map_err\(\|e\| format!\("open \{path:\?\}: \{e\}"\)\)\?\);\n    \{.*?\n    \}\n\n    let encryption = if existed \{\n        resolve_existing_box\(&db, encryption_key\)\n    \} else \{\n        initialize_new_box\(&db, encryption_key\)\n    \};',
    '''    let db = Arc::new(Database::create(&path).map_err(|e| format!("open {path:?}: {e}"))?);
    let had_data_table = if existed {
        let read = db.begin_read().map_err(|e| e.to_string())?;
        read.open_table(DATA).is_ok()
    } else {
        false
    };

    let encryption = if existed && had_data_table {
        {
            let write = db.begin_write().map_err(|e| e.to_string())?;
            write.open_table(DATA).map_err(|e| e.to_string())?;
            write.open_table(META).map_err(|e| e.to_string())?;
            write.commit().map_err(|e| e.to_string())?;
        }
        resolve_existing_box(&db, encryption_key)
    } else {
        // A file without the data table is an interrupted first creation,
        // not a legacy plaintext box. Re-run the atomic initializer.
        initialize_new_box(&db, encryption_key)
    };''',
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit(f'open replacement count={count}')

old_cleanup = 'if !existed {\n                let _ = fs::remove_file(&path);\n            }'
if old_cleanup not in text:
    raise SystemExit('cleanup block not found')
text = text.replace(
    old_cleanup,
    'if !existed || !had_data_table {\n                let _ = fs::remove_file(&path);\n            }',
    1,
)

if text.count('encryption.encode_value(value)?') != 2:
    raise SystemExit('unexpected encode_value call count')
text = text.replace('encryption.encode_value(value)?', 'encryption.encode_value(key, value)?')

if text.count('encryption.decode_value(&payload)?') != 1:
    raise SystemExit('unexpected decode_value call count')
text = text.replace('encryption.decode_value(&payload)?', 'encryption.decode_value(key, &payload)?')

marker = '    #[cfg(feature = "encryption")]\n    #[test]\n    fn tampered_encrypted_value_is_rejected() {'
if marker not in text:
    raise SystemExit('tamper test marker not found')
swap_test = '''    #[cfg(feature = "encryption")]
    #[test]
    fn swapping_encrypted_payloads_between_keys_is_rejected() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("swap", Some("password")).unwrap();
        put("swap", "a", &pack(&"first")).unwrap();
        put("swap", "b", &pack(&"second")).unwrap();

        let (db, _) = database("swap").unwrap();
        let (payload_a, payload_b) = {
            let read = db.begin_read().unwrap();
            let table = read.open_table(DATA).unwrap();
            (
                table.get("a").unwrap().unwrap().value().to_vec(),
                table.get("b").unwrap().unwrap().value().to_vec(),
            )
        };
        let write = db.begin_write().unwrap();
        {
            let mut table = write.open_table(DATA).unwrap();
            table.insert("a", payload_b.as_slice()).unwrap();
            table.insert("b", payload_a.as_slice()).unwrap();
        }
        write.commit().unwrap();

        assert!(get("swap", "a").is_err());
        assert!(get("swap", "b").is_err());
        drop(db);
        close("swap");
    }

'''
text = text.replace(marker, swap_test + marker, 1)

path.write_text(text)
