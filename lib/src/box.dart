import 'dart:async';
import 'dart:typed_data';

import 'box_event.dart';
import 'codec.dart';
import 'native_api.dart';

final class BoxMetadata {
  List<String> keys = const <String>[];
}

final class Box {
  Box.internal({
    required this.name,
    required NativeDxtrApi api,
    required BoxMetadata metadata,
    required void Function() onClose,
  })  : _api = api,
        _metadata = metadata,
        _onClose = onClose;

  final String name;
  final NativeDxtrApi _api;
  final BoxMetadata _metadata;
  final void Function() _onClose;
  final StreamController<BoxEvent> _events =
      StreamController<BoxEvent>.broadcast(sync: true);

  bool _closed = false;
  Future<void>? _closeFuture;

  int get length => _metadata.keys.length;
  bool get isEmpty => _metadata.keys.isEmpty;
  Iterable<String> get keys => _metadata.keys;

  /// Values are fetched from redb; the box contents are never retained wholesale in Dart RAM.
  Future<List<dynamic>> get values async {
    _ensureOpen();
    final result = <dynamic>[];
    for (final key in _metadata.keys) {
      result.add(await get(key));
    }
    return result;
  }

  Future<void> refreshMetadata() async {
    _ensureOpen();
    _metadata.keys = List<String>.unmodifiable(await _api.getAllKeys(name));
  }

  Future<void> put(String key, dynamic value) async {
    _ensureOpen();
    _validateKey(key);
    await _api.put(name, key, DxtrCodec.encode(value));
    if (!_metadata.keys.contains(key)) {
      _metadata.keys = List<String>.unmodifiable(<String>[
        ..._metadata.keys,
        key,
      ]);
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
    final set = <String>{..._metadata.keys, ...entries.keys};
    _metadata.keys = List<String>.unmodifiable(set);
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
    _metadata.keys = List<String>.unmodifiable(
      _metadata.keys.where((item) => item != key),
    );
    _events.add(BoxEvent(boxName: name, type: BoxEventType.delete, key: key));
  }

  Future<void> clear() async {
    _ensureOpen();
    await _api.clear(name);
    _metadata.keys = const <String>[];
    _events.add(BoxEvent(boxName: name, type: BoxEventType.clear));
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    final inFlight = _closeFuture;
    if (inFlight != null) return inFlight;

    final future = _performClose();
    _closeFuture = future;
    return future;
  }

  Future<void> _performClose() async {
    try {
      await _api.closeBox(name);
      _closed = true;
      _onClose();
      await _events.close();
    } catch (_) {
      _closeFuture = null;
      rethrow;
    }
  }

  Future<List<MapEntry<String, dynamic>>> where(
    bool Function(dynamic) test,
  ) async {
    _ensureOpen();
    final result = <MapEntry<String, dynamic>>[];
    for (final key in _metadata.keys) {
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

  void _ensureOpen() {
    if (_closed) throw StateError('Box "$name" is closed.');
  }

  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key cannot be empty');
    }
  }
}
