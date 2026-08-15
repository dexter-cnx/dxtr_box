import 'dart:typed_data';

/// Small seam over generated flutter_rust_bridge symbols.
///
/// `tool/wire_generated_api.sh` replaces this implementation after FRB codegen.
abstract interface class NativeDxtrApi {
  Future<void> initDb(String path);
  Future<void> openBox(String name, {String? encryptionKey});
  Future<void> closeBox(String name);
  Future<void> deleteBox(String name);
  Future<bool> boxExists(String name);
  Future<void> put(String boxName, String key, Uint8List value);
  Future<void> putAll(String boxName, Map<String, Uint8List> values);
  Future<Uint8List?> get(String boxName, String key);
  Future<bool> containsKey(String boxName, String key);
  Future<void> delete(String boxName, String key);
  Future<void> clear(String boxName);
  Future<List<String>> getAllKeys(String boxName);
  Future<int> length(String boxName);
}

final class UnavailableNativeDxtrApi implements NativeDxtrApi {
  const UnavailableNativeDxtrApi();

  Never _missing() => throw StateError(
        'dxtr_box Rust bindings are not generated. Run '
        '`flutter_rust_bridge_codegen generate` and wire lib/src/rust via '
        'tool/wire_generated_api.sh.',
      );

  @override Future<void> initDb(String path) async => _missing();
  @override Future<void> openBox(String name, {String? encryptionKey}) async => _missing();
  @override Future<void> closeBox(String name) async => _missing();
  @override Future<void> deleteBox(String name) async => _missing();
  @override Future<bool> boxExists(String name) async => _missing();
  @override Future<void> put(String boxName, String key, Uint8List value) async => _missing();
  @override Future<void> putAll(String boxName, Map<String, Uint8List> values) async => _missing();
  @override Future<Uint8List?> get(String boxName, String key) async => _missing();
  @override Future<bool> containsKey(String boxName, String key) async => _missing();
  @override Future<void> delete(String boxName, String key) async => _missing();
  @override Future<void> clear(String boxName) async => _missing();
  @override Future<List<String>> getAllKeys(String boxName) async => _missing();
  @override Future<int> length(String boxName) async => _missing();
}
