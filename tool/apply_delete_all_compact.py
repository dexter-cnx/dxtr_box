from pathlib import Path
import re

# Rust storage engine
path = Path('rust/src/db.rs')
text = path.read_text()

marker = 'pub fn clear(name: &str) -> Result<(), String> {'
if marker not in text:
    raise SystemExit('db clear marker not found')
insert = '''pub fn delete_all(name: &str, keys: &[String]) -> Result<Vec<String>, String> {
    let (db, _) = database(name)?;
    let write = db.begin_write().map_err(|e| e.to_string())?;
    let mut deleted = Vec::new();
    {
        let mut table = write.open_table(DATA).map_err(|e| e.to_string())?;
        for key in keys {
            if table
                .remove(key.as_str())
                .map_err(|e| e.to_string())?
                .is_some()
            {
                deleted.push(key.clone());
            }
        }
    }
    write.commit().map_err(|e| e.to_string())?;
    Ok(deleted)
}

'''
text = text.replace(marker, insert + marker, 1)

marker = 'pub fn all_keys(name: &str) -> Result<Vec<String>, String> {'
if marker not in text:
    raise SystemExit('db all_keys marker not found')
insert = '''pub fn compact(name: &str) -> Result<bool, String> {
    let mut databases = DATABASES.write();
    let entry = databases
        .get_mut(name)
        .ok_or_else(|| format!("box '{name}' is not open"))?;
    if entry.handles != 1 {
        return Err("compact requires exactly one open box handle".to_string());
    }
    let db = Arc::get_mut(&mut entry.db)
        .ok_or_else(|| "box is busy; retry compact when no operations are in flight".to_string())?;

    let mut compacted = false;
    while db.compact().map_err(|e| e.to_string())? {
        compacted = true;
    }
    Ok(compacted)
}

'''
text = text.replace(marker, insert + marker, 1)

# Rust tests
marker = '    #[test]\n    fn clear_is_atomic_write_transaction() {'
if marker not in text:
    raise SystemExit('db clear test marker not found')
tests = '''    #[test]
    fn delete_all_is_atomic_and_reports_existing_keys() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("batch-delete", None).unwrap();
        put_all(
            "batch-delete",
            &[
                ("a".into(), pack(&1_i64)),
                ("b".into(), pack(&2_i64)),
                ("c".into(), pack(&3_i64)),
            ],
        )
        .unwrap();

        let deleted = delete_all(
            "batch-delete",
            &["a".to_string(), "missing".to_string(), "c".to_string()],
        )
        .unwrap();
        assert_eq!(deleted, vec!["a".to_string(), "c".to_string()]);
        assert_eq!(all_keys("batch-delete").unwrap(), vec!["b".to_string()]);
        close("batch-delete");
    }

    #[test]
    fn compact_requires_a_single_idle_handle() {
        let _guard = TEST_LOCK.lock();
        let dir = tempfile::tempdir().unwrap();
        init(dir.path().to_str().unwrap()).unwrap();
        open("compact", None).unwrap();
        put_all(
            "compact",
            &(0..128)
                .map(|index| (format!("key-{index}"), pack(&vec![index as u8; 1024])))
                .collect::<Vec<_>>(),
        )
        .unwrap();
        clear("compact").unwrap();

        assert!(compact("compact").is_ok());
        open("compact", None).unwrap();
        assert!(compact("compact").is_err());
        close("compact");
        close("compact");
    }

'''
text = text.replace(marker, tests + marker, 1)
path.write_text(text)

# Rust FRB API
path = Path('rust/src/api.rs')
text = path.read_text()
marker = 'pub fn clear(box_name: String) -> Result<(), String> {'
if marker not in text:
    raise SystemExit('api clear marker not found')
insert = '''pub fn delete_all(box_name: String, keys: Vec<String>) -> Result<Vec<String>, String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    let deleted = db::delete_all(&box_name, &keys)?;
    for key in &deleted {
        emit_event(NativeBoxEvent {
            box_name: box_name.clone(),
            event_type: NativeBoxEventType::Delete,
            key: Some(key.clone()),
            value: None,
        });
    }
    Ok(deleted)
}

'''
text = text.replace(marker, insert + marker, 1)

marker = 'pub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {'
if marker not in text:
    raise SystemExit('api get_all_keys marker not found')
insert = '''pub fn compact(box_name: String) -> Result<bool, String> {
    let mutation_lock = mutation_lock(&box_name);
    let _mutation_guard = mutation_lock.lock();
    db::compact(&box_name)
}

'''
text = text.replace(marker, insert + marker, 1)
path.write_text(text)

# Dart native seam
path = Path('lib/src/native_api.dart')
text = path.read_text()
text = text.replace(
    '  Future<void> delete(String boxName, String key);\n  Future<void> clear(String boxName);',
    '  Future<void> delete(String boxName, String key);\n  Future<List<String>> deleteAll(String boxName, List<String> keys);\n  Future<void> clear(String boxName);\n  Future<bool> compact(String boxName);',
    1,
)

prod_marker = '''  @override
  Future<void> clear(String boxName) async {'''
if prod_marker not in text:
    raise SystemExit('native production clear marker not found')
prod_insert = '''  @override
  Future<List<String>> deleteAll(String boxName, List<String> keys) async {
    await _ensureInitialized();
    return frb.deleteAll(boxName: boxName, keys: keys);
  }

'''
text = text.replace(prod_marker, prod_insert + prod_marker, 1)

prod_marker = '''  @override
  Future<List<String>> getAllKeys(String boxName) async {'''
prod_insert = '''  @override
  Future<bool> compact(String boxName) async {
    await _ensureInitialized();
    return frb.compact(boxName: boxName);
  }

'''
text = text.replace(prod_marker, prod_insert + prod_marker, 1)

unavailable_marker = '  @override\n  Future<void> clear(String boxName) async => _missing();'
unavailable_insert = '''  @override
  Future<List<String>> deleteAll(String boxName, List<String> keys) async =>
      _missing();

'''
text = text.replace(unavailable_marker, unavailable_insert + unavailable_marker, 1)
unavailable_marker = '  @override\n  Future<List<String>> getAllKeys(String boxName) async => _missing();'
unavailable_insert = '''  @override
  Future<bool> compact(String boxName) async => _missing();

'''
text = text.replace(unavailable_marker, unavailable_insert + unavailable_marker, 1)
path.write_text(text)

# Public Box API
path = Path('lib/src/box.dart')
text = path.read_text()
marker = '  Future<void> clear() async {'
if marker not in text:
    raise SystemExit('box clear marker not found')
insert = '''  Future<void> deleteAll(Iterable<String> keys) async {
    _ensureOpen();
    final unique = <String>[];
    final seen = <String>{};
    for (final key in keys) {
      _validateKey(key);
      if (seen.add(key)) unique.add(key);
    }
    if (unique.isEmpty) return;

    final deleted = await _api.deleteAll(name, unique);
    if (deleted.isEmpty) return;
    final deletedSet = deleted.toSet();
    _metadata.keys = List<String>.unmodifiable(
      _metadata.keys.where((item) => !deletedSet.contains(item)),
    );
  }

'''
text = text.replace(marker, insert + marker, 1)
marker = '  Future<void> close() {'
insert = '''  Future<bool> compact() async {
    _ensureOpen();
    return _api.compact(name);
  }

'''
text = text.replace(marker, insert + marker, 1)
path.write_text(text)

# Fake native API used by Dart tests: add methods by matching the existing clear/getAllKeys methods.
path = Path('test/box_test.dart')
text = path.read_text()
clear_marker = '  Future<void> clear(String boxName) async {'
if clear_marker not in text:
    raise SystemExit('fake clear marker not found')
insert = '''  @override
  Future<List<String>> deleteAll(String boxName, List<String> keys) async {
    final box = boxes[boxName];
    if (box == null) throw StateError('box not open');
    final deleted = <String>[];
    for (final key in keys) {
      if (box.remove(key) != null) {
        deleted.add(key);
        emit(NativeWatchEvent(
          boxName: boxName,
          type: NativeWatchEventType.delete,
          key: key,
        ));
      }
    }
    return deleted;
  }

'''
text = text.replace(clear_marker, insert + clear_marker, 1)
get_keys_marker = '  Future<List<String>> getAllKeys(String boxName) async {'
insert = '''  @override
  Future<bool> compact(String boxName) async {
    if (!boxes.containsKey(boxName)) throw StateError('box not open');
    return false;
  }

'''
text = text.replace(get_keys_marker, insert + get_keys_marker, 1)

# Add public API regression test before close tests.
test_marker = "    test('clear removes all values', () async {"
if test_marker not in text:
    raise SystemExit('box test marker not found')
tests = '''    test('deleteAll removes existing keys and keeps metadata coherent', () async {
      final box = await DxtrBox.open('batch');
      await box.putAll({'a': 1, 'b': 2, 'c': 3});

      await box.deleteAll(['a', 'missing', 'c', 'a']);

      expect(box.keys, ['b']);
      expect(await box.get('a'), isNull);
      expect(await box.get('b'), 2);
      await box.close();
    });

    test('compact delegates to native engine', () async {
      final box = await DxtrBox.open('compact');
      expect(await box.compact(), isFalse);
      await box.close();
    });

'''
text = text.replace(test_marker, tests + test_marker, 1)
path.write_text(text)
