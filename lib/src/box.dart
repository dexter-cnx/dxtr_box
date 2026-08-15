import 'dart:async';
import 'dart:typed_data';

import 'box_event.dart';
import 'codec.dart';
import 'native_api.dart';

final class Box {
  Box.internal({
    required this.name,
    required NativeDxtrApi api,
    required bool lazy,
  }) : _api = api,
       _lazy = lazy;

  final String name;
  final NativeDxtrApi _api;
  final bool _lazy;
  final StreamController<BoxEvent> _events =
      StreamController<BoxEvent>.broadcast(sync: true);

  List<String> _keys = const <String>[];
  bool _closed = false;

  int get length => _keys.length;
  bool get isEmpty => _keys.isEmpty;
  Iterable<String> get keys => _keys;

  /// Values are fetched from redb; the box contents are never retained wholesale in Dart RAM.
  Future<List<dynamic>> get values async {
    _ensureOpen();
    final result = <dynamic>[];
    for (final key in _keys) {
      result.add(await get(key));
    }
    return result;
  }

  Future<void> refreshMetadata() async {
    _ensureOpen();
    _keys = List<String>.unmodifiable(await _api.getAllKeys(name));
  }

  Future<void> put(String key, dynamic value) async {
    _ensureOpen();
    _validateKey(key);
    await _api.put(name, key, DxtrCodec.encode(value));
    if (!_keys.contains(key)) {
      _keys = List<String>.unmodifiable(<String>[..._keys, key]);
    }
    _events.add(
      BoxEvent(boxName: name, type: BoxEventType.put, key: key, value: value),
    );
  }

  Future<void> putAll(Map<String, dynamic> entries) async {
    _ensureOpen();
    final encoded = <String, Uint8List>{};
    for (final entry in entries.entries) {
      _validateKey(entry.key);
      encoded[entry.key] = DxtrCodec.encode(entry.value);
    }
    await _api.putAll(name, encoded);
    final set = <String>{..._keys, ...entries.keys};
    _keys = List<String>.unmodifiable(set);
    for (final entry in entries.entries) {
      _events.add(
        BoxEvent(
          boxName: name,
          type: BoxEventType.put,
          key: entry.key,
          value: entry.value,
        ),
      );
    }
  }

  Future<dynamic> get(String key, {dynamic defaultValue}) async {
    _ensureOpen();
    _validateKey(key);
    final bytes = await _api.get(name, key);
    return bytes == null ? defaultValue : DxtrCodec.decode(bytes);
  }

  Future<bool> containsKey(String key) async {
    _ensureOpen();
    _validateKey(key);
    return _api.containsKey(name, key);
  }

  Future<void> delete(String key) async {
    _ensureOpen();
    _validateKey(key);
    await _api.delete(name, key);
    _keys = List<String>.unmodifiable(_keys.where((item) => item != key));
    _events.add(BoxEvent(boxName: name, type: BoxEventType.delete, key: key));
  }

  Future<void> clear() async {
    _ensureOpen();
    await _api.clear(name);
    _keys = const <String>[];
    _events.add(BoxEvent(boxName: name, type: BoxEventType.clear));
  }

  Future<void> close() async {
    if (_closed) return;
    await _api.closeBox(name);
    _closed = true;
    await _events.close();
  }

  Future<List<MapEntry<String, dynamic>>> where(
    bool Function(dynamic) test,
  ) async {
    _ensureOpen();
    final result = <MapEntry<String, dynamic>>[];
    for (final key in _keys) {
      final value = await get(key);
      if (test(value)) result.add(MapEntry<String, dynamic>(key, value));
    }
    return result;
  }

  Stream<BoxEvent> watch({String? key}) {
    _ensureOpen();
    if (key == null) return _events.stream;
    return _events.stream.where(
      (event) => event.key == key || event.type == BoxEventType.clear,
    );
  }

  bool get lazy => _lazy;

  void _ensureOpen() {
    if (_closed) throw StateError('Box "$name" is closed.');
  }

  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key cannot be empty');
    }
  }
}
