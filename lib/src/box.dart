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
    required String watcherId,
    required NativeDxtrApi api,
    required BoxMetadata metadata,
    required void Function() onClose,
  })  : _watcherId = watcherId,
        _api = api,
        _metadata = metadata,
        _onClose = onClose;

  final String name;
  final String _watcherId;
  final NativeDxtrApi _api;
  final BoxMetadata _metadata;
  final void Function() _onClose;
  final StreamController<BoxEvent> _events =
      StreamController<BoxEvent>.broadcast(sync: true);

  final List<NativeWatchEvent> _pendingWatchEvents = <NativeWatchEvent>[];
  StreamSubscription<NativeWatchEvent>? _nativeWatchSubscription;
  bool _nativeWatchRegistered = false;
  bool _metadataHydrated = false;
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

  Future<void> initializeNativeWatch() async {
    _ensureOpen();
    final nativeStream = await _api.watchBox(name, _watcherId);
    _nativeWatchRegistered = true;
    _nativeWatchSubscription = nativeStream.listen(
      _handleNativeWatchEvent,
      onError: (Object error, StackTrace stackTrace) {
        if (!_events.isClosed) {
          _events.addError(error, stackTrace);
        }
      },
    );
  }

  Future<void> disposeNativeWatch() async {
    final subscription = _nativeWatchSubscription;
    _nativeWatchSubscription = null;

    // Drop the native StreamSink first so FRB can close the producer side
    // before Dart tears down its subscription. Reversing this order can leave
    // cancellation waiting on a producer that is still retained in Rust.
    if (_nativeWatchRegistered) {
      await _api.unwatchBox(name, _watcherId);
      _nativeWatchRegistered = false;
    }
    if (subscription != null) {
      await subscription.cancel();
    }
    _pendingWatchEvents.clear();
  }

  Future<void> refreshMetadata() async {
    _ensureOpen();
    final snapshot = await _api.getAllKeys(name);
    _metadata.keys = List<String>.unmodifiable(snapshot);

    // Events can arrive after watch registration but before the metadata read
    // completes. Replaying them after assigning the snapshot prevents a stale
    // snapshot from overwriting a committed mutation. Key transformations are
    // idempotent, so replay is correct whether the snapshot was taken before,
    // during, or after any buffered event.
    _metadataHydrated = true;
    final pending = List<NativeWatchEvent>.of(_pendingWatchEvents);
    _pendingWatchEvents.clear();
    for (final event in pending) {
      _applyNativeWatchEvent(event);
    }
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
  }

  Future<void> deleteAll(Iterable<String> keys) async {
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

  Future<void> clear() async {
    _ensureOpen();
    await _api.clear(name);
    _metadata.keys = const <String>[];
  }

  Future<bool> compact() async {
    _ensureOpen();
    return _api.compact(name);
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
      await disposeNativeWatch();
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

  void _handleNativeWatchEvent(NativeWatchEvent event) {
    if (_closed || event.boxName != name) {
      return;
    }
    if (!_metadataHydrated) {
      _pendingWatchEvents.add(event);
      return;
    }
    _applyNativeWatchEvent(event);
  }

  void _applyNativeWatchEvent(NativeWatchEvent event) {
    switch (event.type) {
      case NativeWatchEventType.put:
        final key = event.key;
        final bytes = event.value;
        if (key == null || bytes == null) {
          _addWatchProtocolError('put event requires key and value');
          return;
        }
        if (!_metadata.keys.contains(key)) {
          _metadata.keys = List<String>.unmodifiable(<String>[
            ..._metadata.keys,
            key,
          ]);
        }
        _events.add(
          BoxEvent(
            boxName: name,
            type: BoxEventType.put,
            key: key,
            value: DxtrCodec.decode(bytes),
          ),
        );
      case NativeWatchEventType.delete:
        final key = event.key;
        if (key == null) {
          _addWatchProtocolError('delete event requires key');
          return;
        }
        _metadata.keys = List<String>.unmodifiable(
          _metadata.keys.where((item) => item != key),
        );
        _events.add(
          BoxEvent(boxName: name, type: BoxEventType.delete, key: key),
        );
      case NativeWatchEventType.clear:
        _metadata.keys = const <String>[];
        _events.add(BoxEvent(boxName: name, type: BoxEventType.clear));
    }
  }

  void _addWatchProtocolError(String message) {
    if (!_events.isClosed) {
      _events.addError(StateError('Invalid native watch event: $message'));
    }
  }

  void _ensureOpen() {
    if (_closed || _closeFuture != null) {
      throw StateError('Box "$name" is closing or closed.');
    }
  }

  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Key cannot be empty');
    }
  }
}
