from pathlib import Path


def replace(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"expected text not found in {path}: {old[:120]!r}")
    file.write_text(text.replace(old, new, 1))


if "pub fn get_all(name: &str, keys: &[String])" in Path("rust/src/db.rs").read_text():
    raise SystemExit(0)

replace(
    "lib/src/native_api.dart",
    "final class NativeQueryRecord {\n  const NativeQueryRecord({required this.key, required this.value});\n\n  final String key;\n  final Uint8List value;\n}\n",
    "final class NativeQueryRecord {\n  const NativeQueryRecord({required this.key, required this.value});\n\n  final String key;\n  final Uint8List value;\n}\n\nfinal class NativeBatchRecord {\n  const NativeBatchRecord({required this.key, required this.value});\n\n  final String key;\n  final Uint8List value;\n}\n",
)
replace(
    "lib/src/native_api.dart",
    "abstract interface class NativeQueryApi {\n",
    "abstract interface class NativeBatchReadApi {\n  Future<List<NativeBatchRecord>> getAll(String boxName, List<String> keys);\n}\n\nabstract interface class NativeQueryApi {\n",
)
replace(
    "lib/src/native_api.dart",
    "        NativeDxtrApi,\n        NativeQueryApi,\n",
    "        NativeDxtrApi,\n        NativeBatchReadApi,\n        NativeQueryApi,\n",
)
replace(
    "lib/src/native_api.dart",
    "  @override\n  Future<bool> containsKey(String boxName, String key) async {\n    await _ensureInitialized();\n    return frb.containsKey(boxName: boxName, key: key);\n  }\n",
    "  @override\n  Future<bool> containsKey(String boxName, String key) async {\n    await _ensureInitialized();\n    return frb.containsKey(boxName: boxName, key: key);\n  }\n\n  @override\n  Future<List<NativeBatchRecord>> getAll(\n    String boxName,\n    List<String> keys,\n  ) async {\n    await _ensureInitialized();\n    final records = await frb.getAll(boxName: boxName, keys: keys);\n    return records\n        .map(\n          (record) => NativeBatchRecord(\n            key: record.key,\n            value: Uint8List.fromList(record.value),\n          ),\n        )\n        .toList(growable: false);\n  }\n",
)

replace(
    "lib/src/box.dart",
    "  Future<bool> containsKey(String key) async {\n    _ensureOpen();\n    _validateKey(key);\n    return _api.containsKey(name, key);\n  }\n",
    "  Future<bool> containsKey(String key) async {\n    _ensureOpen();\n    _validateKey(key);\n    return _api.containsKey(name, key);\n  }\n\n  /// Fetches multiple authoritative values using one native batch read.\n  ///\n  /// Results preserve input order for hits. Missing keys are omitted and\n  /// duplicate input keys produce duplicate result entries.\n  Future<List<MapEntry<String, dynamic>>> getAll(Iterable<String> keys) async {\n    _ensureOpen();\n    if (_api is! NativeBatchReadApi) {\n      throw UnsupportedError(\n        'The configured native engine does not support batch reads.',\n      );\n    }\n\n    final requested = keys.toList(growable: false);\n    for (final key in requested) {\n      _validateKey(key);\n    }\n    if (requested.isEmpty) {\n      return const <MapEntry<String, dynamic>>[];\n    }\n\n    final records = await (_api as NativeBatchReadApi).getAll(name, requested);\n    return records\n        .map(\n          (record) => MapEntry<String, dynamic>(\n            record.key,\n            DxtrCodec.decode(record.value),\n          ),\n        )\n        .toList(growable: false);\n  }\n",
)

replace(
    "rust/src/api.rs",
    "pub struct NativeQueryRecord {\n    pub key: String,\n    pub value: Vec<u8>,\n}\n",
    "pub struct NativeQueryRecord {\n    pub key: String,\n    pub value: Vec<u8>,\n}\n\npub struct NativeBatchRecord {\n    pub key: String,\n    pub value: Vec<u8>,\n}\n",
)
replace(
    "rust/src/api.rs",
    "#[frb(sync)]\npub fn contains_key(box_name: String, key: String) -> Result<bool, String> {\n    db::contains_key(&box_name, &key)\n}\n",
    "#[frb(sync)]\npub fn contains_key(box_name: String, key: String) -> Result<bool, String> {\n    db::contains_key(&box_name, &key)\n}\n\npub fn get_all(box_name: String, keys: Vec<String>) -> Result<Vec<NativeBatchRecord>, String> {\n    db::get_all(&box_name, &keys).map(|records| {\n        records\n            .into_iter()\n            .map(|(key, value)| NativeBatchRecord { key, value })\n            .collect()\n    })\n}\n",
)

old_get = """pub fn get(name: &str, key: &str) -> Result<Option<Vec<u8>>, String> {
    let (db, encryption) = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    let stored = table
        .get(key)
        .map_err(|e| e.to_string())?
        .map(|guard| guard.value().to_vec());
    drop(table);
    drop(read);

    match stored {
        None => Ok(None),
        Some(payload) => {
            let plaintext = encryption.decode_value(key, &payload)?;
            validate_message_pack(&plaintext)?;
            Ok(Some(plaintext))
        }
    }
}
"""
new_get = old_get + """
pub fn get_all(name: &str, keys: &[String]) -> Result<Vec<(String, Vec<u8>)>, String> {
    let (db, encryption) = database(name)?;
    let read = db.begin_read().map_err(|e| e.to_string())?;
    let table = read.open_table(DATA).map_err(|e| e.to_string())?;
    let mut records = Vec::with_capacity(keys.len());

    for key in keys {
        let Some(stored) = table
            .get(key.as_str())
            .map_err(|e| e.to_string())?
            .map(|guard| guard.value().to_vec())
        else {
            continue;
        };
        let plaintext = encryption.decode_value(key, &stored)?;
        validate_message_pack(&plaintext)?;
        records.push((key.clone(), plaintext));
    }

    Ok(records)
}
"""
replace("rust/src/db.rs", old_get, new_get)

replace(
    "test/box_test.dart",
    "final class _FakeNativeDxtrApi implements NativeDxtrApi {\n",
    "final class _FakeNativeDxtrApi implements NativeDxtrApi, NativeBatchReadApi {\n",
)
replace(
    "test/box_test.dart",
    "  test('get returns default value for a missing key', () async {\n    final box = await DxtrBox.open('settings');\n    expect(await box.get('missing', defaultValue: 'fallback'), 'fallback');\n  });\n",
    "  test('get returns default value for a missing key', () async {\n    final box = await DxtrBox.open('settings');\n    expect(await box.get('missing', defaultValue: 'fallback'), 'fallback');\n  });\n\n  test('getAll preserves input order, duplicates, and omits misses', () async {\n    final box = await DxtrBox.open('batch-read');\n    await box.putAll(<String, dynamic>{'a': 1, 'b': 2, 'c': 3});\n\n    final values = await box.getAll(<String>['c', 'missing', 'a', 'c']);\n\n    expect(values.map((entry) => entry.key), <String>['c', 'a', 'c']);\n    expect(values.map((entry) => entry.value), <int>[3, 1, 3]);\n  });\n",
)
replace(
    "test/box_test.dart",
    "  @override\n  Future<bool> containsKey(String boxName, String key) async {\n    _requireOpen(boxName);\n    return _box(boxName).containsKey(key);\n  }\n",
    "  @override\n  Future<bool> containsKey(String boxName, String key) async {\n    _requireOpen(boxName);\n    return _box(boxName).containsKey(key);\n  }\n\n  @override\n  Future<List<NativeBatchRecord>> getAll(\n    String boxName,\n    List<String> keys,\n  ) async {\n    _requireOpen(boxName);\n    final box = _box(boxName);\n    final records = <NativeBatchRecord>[];\n    for (final key in keys) {\n      final value = box[key];\n      if (value != null) {\n        records.add(\n          NativeBatchRecord(key: key, value: Uint8List.fromList(value)),\n        );\n      }\n    }\n    return records;\n  }\n",
)

native_test = Path("test/native_integration_test.dart")
text = native_test.read_text()
marker = "  test('"
insert = """  test('native getAll preserves order, duplicates, misses, and encryption', () async {
    final dir = await Directory.systemTemp.createTemp('dxtr_box_batch_native_');
    addTearDown(() => dir.delete(recursive: true));

    await DxtrBox.init(path: dir.path);
    final box = await DxtrBox.open('batch-native', encryptionKey: 'secret');
    await box.putAll(<String, dynamic>{'a': 1, 'b': 2, 'c': 3});

    final values = await box.getAll(<String>['b', 'missing', 'a', 'b']);
    expect(values.map((entry) => entry.key), <String>['b', 'a', 'b']);
    expect(values.map((entry) => entry.value), <int>[2, 1, 2]);
    await box.close();
  });

"""
index = text.find(marker)
if index == -1:
    raise SystemExit("could not locate native integration test insertion point")
native_test.write_text(text[:index] + insert + text[index:])

Path("test/batch_read_benchmark_test.dart").write_text(r'''// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled = Platform.environment['DXTR_BOX_BATCH_READ_BENCHMARK'] == '1';

  test('0.5 PR3 batch read matrix', () async {
    if (!enabled) {
      return;
    }

    DxtrBox.bindNativeApi(const FrbNativeDxtrApi());
    final dir = await Directory.systemTemp.createTemp('dxtr_box_batch_bench_');
    addTearDown(() => dir.delete(recursive: true));
    await DxtrBox.init(path: dir.path);
    final box = await DxtrBox.open('batch-bench');

    final entries = <String, dynamic>{
      for (var i = 0; i < 1000; i++)
        'k$i': <String, dynamic>{'id': i, 'value': 'v$i'},
    };
    await box.putAll(entries);

    for (final size in <int>[10, 100, 1000]) {
      final keys = List<String>.generate(size, (i) => 'k$i', growable: false);
      final batch = await _medianMicros(() async {
        final result = await box.getAll(keys);
        if (result.length != size) {
          throw StateError('batch result mismatch');
        }
      });
      final independent = await _medianMicros(() async {
        for (final key in keys) {
          if (await box.get(key) == null) {
            throw StateError('missing independent get');
          }
        }
      });
      print(
        'DXTR_BOX_BATCH_READ {"keys":$size,"batch_us":$batch,'
        '"independent_us":$independent}',
      );
    }

    await box.close();
  });
}

Future<double> _medianMicros(Future<void> Function() body) async {
  const samples = 5;
  final values = <double>[];
  for (var sample = 0; sample < samples; sample++) {
    final stopwatch = Stopwatch()..start();
    await body();
    stopwatch.stop();
    values.add(stopwatch.elapsedMicroseconds.toDouble());
  }
  values.sort();
  return values[values.length ~/ 2];
}
''')

replace(
    "Makefile",
    "benchmark-read-path preflight",
    "benchmark-read-path benchmark-batch-read preflight",
)
replace(
    "Makefile",
    '\t@echo "  make benchmark-read-path  0.5 decomposed Rust + Dart/FRB read-path diagnostics"\n',
    '\t@echo "  make benchmark-read-path  0.5 decomposed Rust + Dart/FRB read-path diagnostics"\n'
    '\t@echo "  make benchmark-batch-read 0.5 PR3 batch read 10/100/1000-key diagnostics"\n',
)
replace(
    "Makefile",
    "\npreflight: ci-fast\n",
    "\nbenchmark-batch-read: native-build pub-get\n"
    '\tLD_LIBRARY_PATH="rust/target/release:$${LD_LIBRARY_PATH:-}" '
    'DYLD_LIBRARY_PATH="rust/target/release:$${DYLD_LIBRARY_PATH:-}" '
    'PATH="rust/target/release:$$PATH" DXTR_BOX_BATCH_READ_BENCHMARK=1 '
    '$(FLUTTER) test test/batch_read_benchmark_test.dart --reporter expanded\n\n'
    "preflight: ci-fast\n",
)
