import 'dart:typed_data';

import 'rust/api.dart' as frb;
import 'rust/frb_generated.dart';

enum NativeWatchEventType { put, delete, clear }

final class NativeWatchEvent {
  const NativeWatchEvent({
    required this.boxName,
    required this.type,
    this.key,
    this.value,
  });

  final String boxName;
  final NativeWatchEventType type;
  final String? key;
  final Uint8List? value;
}

/// Small seam over generated flutter_rust_bridge symbols.
abstract interface class NativeDxtrApi {
  Future<void> initDb(String path);
  Future<void> openBox(String name, {String? encryptionKey});
  Future<void> closeBox(String name);
  Future<void> deleteBox(String name);
  Future<bool> boxExists(String name);
  Future<Stream<NativeWatchEvent>> watchBox(String boxName, String watcherId);
  Future<void> unwatchBox(String boxName, String watcherId);
  Future<void> put(String boxName, String key, Uint8List value);
  Future<void> putAll(String boxName, Map<String, Uint8List> values);
  Future<Uint8List?> get(String boxName, String key);
  Future<bool> containsKey(String boxName, String key);
  Future<void> delete(String boxName, String key);
  Future<void> clear(String boxName);
  Future<List<String>> getAllKeys(String boxName);
  Future<int> length(String boxName);
}

/// Production adapter backed by generated flutter_rust_bridge bindings.
final class FrbNativeDxtrApi implements NativeDxtrApi {
  const FrbNativeDxtrApi();

  static Future<void>? _initializing;

  Future<void> _ensureInitialized() =>
      _initializing ??= RustLib.init().then((_) {});

  @override
  Future<void> initDb(String path) async {
    await _ensureInitialized();
    frb.initDb(path: path);
  }

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async {
    await _ensureInitialized();
    frb.openBox(name: name, encryptionKey: encryptionKey);
  }

  @override
  Future<void> closeBox(String name) async {
    await _ensureInitialized();
    frb.closeBox(name: name);
  }

  @override
  Future<void> deleteBox(String name) async {
    await _ensureInitialized();
    frb.deleteBox(name: name);
  }

  @override
  Future<bool> boxExists(String name) async {
    await _ensureInitialized();
    return frb.boxExists(name: name);
  }

  @override
  Future<Stream<NativeWatchEvent>> watchBox(
    String boxName,
    String watcherId,
  ) async {
    await _ensureInitialized();
    final stream = await frb.watchBox(boxName: boxName, watcherId: watcherId);
    return stream.map(
      (event) => NativeWatchEvent(
        boxName: event.boxName,
        type: switch (event.eventType) {
          frb.NativeBoxEventType.put => NativeWatchEventType.put,
          frb.NativeBoxEventType.delete => NativeWatchEventType.delete,
          frb.NativeBoxEventType.clear => NativeWatchEventType.clear,
        },
        key: event.key,
        value: event.value == null ? null : Uint8List.fromList(event.value!),
      ),
    );
  }

  @override
  Future<void> unwatchBox(String boxName, String watcherId) async {
    await _ensureInitialized();
    frb.unwatchBox(boxName: boxName, watcherId: watcherId);
  }

  @override
  Future<void> put(String boxName, String key, Uint8List value) async {
    await _ensureInitialized();
    await frb.put(boxName: boxName, key: key, value: value);
  }

  @override
  Future<void> putAll(
    String boxName,
    Map<String, Uint8List> values,
  ) async {
    await _ensureInitialized();
    await frb.putAll(
      boxName: boxName,
      entries: values.entries
          .map((entry) => (entry.key, entry.value))
          .toList(growable: false),
    );
  }

  @override
  Future<Uint8List?> get(String boxName, String key) async {
    await _ensureInitialized();
    return frb.get_(boxName: boxName, key: key);
  }

  @override
  Future<bool> containsKey(String boxName, String key) async {
    await _ensureInitialized();
    return frb.containsKey(boxName: boxName, key: key);
  }

  @override
  Future<void> delete(String boxName, String key) async {
    await _ensureInitialized();
    await frb.delete(boxName: boxName, key: key);
  }

  @override
  Future<void> clear(String boxName) async {
    await _ensureInitialized();
    await frb.clear(boxName: boxName);
  }

  @override
  Future<List<String>> getAllKeys(String boxName) async {
    await _ensureInitialized();
    return frb.getAllKeys(boxName: boxName);
  }

  @override
  Future<int> length(String boxName) async {
    await _ensureInitialized();
    final value = await frb.length(boxName: boxName);
    final maxDartInt = BigInt.from(0x7fffffffffffffff);
    if (value.isNegative || value > maxDartInt) {
      throw StateError(
        'Native box length cannot be represented as a Dart int.',
      );
    }
    return value.toInt();
  }
}

/// Test/failure adapter retained so callers can explicitly disable native IO.
final class UnavailableNativeDxtrApi implements NativeDxtrApi {
  const UnavailableNativeDxtrApi();

  Never _missing() =>
      throw StateError('dxtr_box Rust bindings are unavailable.');

  @override
  Future<void> initDb(String path) async => _missing();

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async =>
      _missing();

  @override
  Future<void> closeBox(String name) async => _missing();

  @override
  Future<void> deleteBox(String name) async => _missing();

  @override
  Future<bool> boxExists(String name) async => _missing();

  @override
  Future<Stream<NativeWatchEvent>> watchBox(
    String boxName,
    String watcherId,
  ) async =>
      _missing();

  @override
  Future<void> unwatchBox(String boxName, String watcherId) async => _missing();

  @override
  Future<void> put(String boxName, String key, Uint8List value) async =>
      _missing();

  @override
  Future<void> putAll(
    String boxName,
    Map<String, Uint8List> values,
  ) async =>
      _missing();

  @override
  Future<Uint8List?> get(String boxName, String key) async => _missing();

  @override
  Future<bool> containsKey(String boxName, String key) async => _missing();

  @override
  Future<void> delete(String boxName, String key) async => _missing();

  @override
  Future<void> clear(String boxName) async => _missing();

  @override
  Future<List<String>> getAllKeys(String boxName) async => _missing();

  @override
  Future<int> length(String boxName) async => _missing();
}
