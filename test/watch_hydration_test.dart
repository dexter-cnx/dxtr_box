import 'dart:async';
import 'dart:typed_data';

import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('events received during metadata hydration replay after stale snapshot',
      () async {
    final api = _HydrationRaceNativeApi();
    DxtrBox.bindNativeApi(api);
    await DxtrBox.init(path: '/tmp/dxtr_box_hydration_test');

    final first = await DxtrBox.open('race');
    api.pauseNextMetadataRead();

    final secondFuture = DxtrBox.open('race');
    await api.waitForMetadataRead();

    // getAllKeys already captured an empty snapshot for the second handle, but
    // its native watcher is registered. This mutation must be buffered and
    // replayed after the stale snapshot is assigned.
    await first.put('late', 1);
    api.resumeMetadataRead();

    final second = await secondFuture;
    expect(second.keys, contains('late'));
    expect(first.keys, contains('late'));
    expect(await second.get('late'), 1);

    await first.close();
    await second.close();
  });
}

final class _HydrationRaceNativeApi implements NativeDxtrApi {
  final Map<String, Map<String, Uint8List>> _boxes =
      <String, Map<String, Uint8List>>{};
  final Map<String, int> _openCounts = <String, int>{};
  final Map<String, Map<String, StreamController<NativeWatchEvent>>> _watchers =
      <String, Map<String, StreamController<NativeWatchEvent>>>{};

  Completer<void>? _metadataStarted;
  Completer<void>? _metadataBarrier;

  void pauseNextMetadataRead() {
    _metadataStarted = Completer<void>();
    _metadataBarrier = Completer<void>();
  }

  Future<void> waitForMetadataRead() => _metadataStarted!.future;

  void resumeMetadataRead() {
    _metadataBarrier?.complete();
    _metadataBarrier = null;
  }

  Map<String, Uint8List> _box(String name) =>
      _boxes.putIfAbsent(name, () => <String, Uint8List>{});

  void _requireOpen(String name) {
    if ((_openCounts[name] ?? 0) == 0) {
      throw StateError('box is not open: $name');
    }
  }

  void _emit(NativeWatchEvent event) {
    final controllers =
        _watchers[event.boxName]?.values.toList(growable: false) ??
            const <StreamController<NativeWatchEvent>>[];
    for (final controller in controllers) {
      controller.add(event);
    }
  }

  @override
  Future<void> initDb(String path) async {}

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async {
    _box(name);
    _openCounts[name] = (_openCounts[name] ?? 0) + 1;
  }

  @override
  Future<void> closeBox(String name) async {
    final remaining = (_openCounts[name] ?? 1) - 1;
    if (remaining == 0) {
      _openCounts.remove(name);
    } else {
      _openCounts[name] = remaining;
    }
  }

  @override
  Future<void> deleteBox(String name) async {
    _boxes.remove(name);
  }

  @override
  Future<bool> boxExists(String name) async => _boxes.containsKey(name);

  @override
  Future<Stream<NativeWatchEvent>> watchBox(
    String boxName,
    String watcherId,
  ) async {
    _requireOpen(boxName);
    final controller = StreamController<NativeWatchEvent>.broadcast(sync: true);
    _watchers.putIfAbsent(
      boxName,
      () => <String, StreamController<NativeWatchEvent>>{},
    )[watcherId] = controller;
    return controller.stream;
  }

  @override
  Future<void> unwatchBox(String boxName, String watcherId) async {
    final watchers = _watchers[boxName];
    final controller = watchers?.remove(watcherId);
    if (controller != null) {
      await controller.close();
    }
    if (watchers != null && watchers.isEmpty) {
      _watchers.remove(boxName);
    }
  }

  @override
  Future<void> put(String boxName, String key, Uint8List value) async {
    _requireOpen(boxName);
    final copied = Uint8List.fromList(value);
    _box(boxName)[key] = copied;
    _emit(
      NativeWatchEvent(
        boxName: boxName,
        type: NativeWatchEventType.put,
        key: key,
        value: Uint8List.fromList(copied),
      ),
    );
  }

  @override
  Future<void> putAll(String boxName, Map<String, Uint8List> values) async {
    for (final entry in values.entries) {
      await put(boxName, entry.key, entry.value);
    }
  }

  @override
  Future<Uint8List?> get(String boxName, String key) async {
    _requireOpen(boxName);
    final value = _box(boxName)[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<bool> containsKey(String boxName, String key) async {
    _requireOpen(boxName);
    return _box(boxName).containsKey(key);
  }

  @override
  Future<void> delete(String boxName, String key) async {
    _requireOpen(boxName);
    _box(boxName).remove(key);
    _emit(
      NativeWatchEvent(
        boxName: boxName,
        type: NativeWatchEventType.delete,
        key: key,
      ),
    );
  }

  @override
  Future<void> clear(String boxName) async {
    _requireOpen(boxName);
    _box(boxName).clear();
    _emit(
      NativeWatchEvent(boxName: boxName, type: NativeWatchEventType.clear),
    );
  }

  @override
  Future<List<String>> getAllKeys(String boxName) async {
    _requireOpen(boxName);
    final snapshot = _box(boxName).keys.toList(growable: false);
    final started = _metadataStarted;
    final barrier = _metadataBarrier;
    if (started != null && !started.isCompleted) {
      started.complete();
      _metadataStarted = null;
    }
    if (barrier != null) {
      await barrier.future;
    }
    return snapshot;
  }

  @override
  Future<int> length(String boxName) async {
    _requireOpen(boxName);
    return _box(boxName).length;
  }
}
