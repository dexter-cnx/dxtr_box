import 'dart:async';
import 'dart:typed_data';

import 'package:dxtr_box/src/box_event.dart';
import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeNativeDxtrApi api;

  setUp(() async {
    api = _FakeNativeDxtrApi();
    DxtrBox.bindNativeApi(api);
    await DxtrBox.init(path: '/tmp/dxtr_box_test');
  });

  test('lazy mode is rejected before native open', () async {
    await expectLater(
      DxtrBox.open('lazy', lazy: true),
      throwsA(isA<UnsupportedError>()),
    );
    expect(await DxtrBox.boxExists('lazy'), isFalse);
  });

  test('open hydrates metadata and CRUD keeps metadata in sync', () async {
    api.seed('people', <String, Uint8List>{
      'alice': _bytes(<int>[1]),
    });

    final box = await DxtrBox.open('people');
    expect(box.length, 1);
    expect(box.keys, orderedEquals(<String>['alice']));

    await box.put('bob', 42);
    expect(box.length, 2);
    expect(await box.get('bob'), 42);
    expect(await box.containsKey('bob'), isTrue);

    await box.delete('alice');
    expect(box.keys, orderedEquals(<String>['bob']));

    await box.clear();
    expect(box.isEmpty, isTrue);
  });

  test('multiple handles share metadata and survive one close', () async {
    final first = await DxtrBox.open('shared');
    final second = await DxtrBox.open('shared');

    await first.put('one', 1);
    expect(second.keys, orderedEquals(<String>['one']));

    await second.put('two', 2);
    expect(first.keys, orderedEquals(<String>['one', 'two']));

    await first.close();
    await second.put('three', 3);
    expect(await second.get('three'), 3);
    expect(second.length, 3);
  });

  test('concurrent close calls share one native teardown', () async {
    final first = await DxtrBox.open('shared-close');
    final second = await DxtrBox.open('shared-close');
    api.pauseClose();

    final firstClose = first.close();
    final duplicateClose = first.close();
    await Future<void>.delayed(Duration.zero);

    expect(api.closeCalls, 1);
    api.resumeClose();
    await Future.wait(<Future<void>>[firstClose, duplicateClose]);

    await second.put('still-open', 1);
    expect(await second.get('still-open'), 1);
  });

  test('get returns default value for a missing key', () async {
    final box = await DxtrBox.open('settings');
    expect(await box.get('missing', defaultValue: 'fallback'), 'fallback');
  });

  test('putAll and where operate over decoded values', () async {
    final box = await DxtrBox.open('scores');
    await box.putAll(<String, dynamic>{'a': 10, 'b': 20, 'c': 30});

    final matches = await box.where((value) => value is int && value >= 20);
    expect(
      matches.map((entry) => entry.key),
      orderedEquals(<String>['b', 'c']),
    );
    expect(
      matches.map((entry) => entry.value),
      orderedEquals(<int>[20, 30]),
    );
  });

  test('watch(key:) filters puts but still forwards clear', () async {
    final box = await DxtrBox.open('events');
    final events = <BoxEvent>[];
    final subscription = box.watch(key: 'tracked').listen(events.add);

    await box.put('tracked', 1);
    await box.put('ignored', 2);
    await box.delete('ignored');
    await box.clear();
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(2));
    expect(events[0].type, BoxEventType.put);
    expect(events[0].key, 'tracked');
    expect(events[1].type, BoxEventType.clear);

    await subscription.cancel();
  });

  test('close is idempotent and rejects later operations', () async {
    final box = await DxtrBox.open('closable');
    await box.close();
    await box.close();

    expect(api.closeCalls, 1);
    expect(() => box.watch(), throwsStateError);
    await expectLater(box.get('key'), throwsStateError);
  });

  test('changing base path is blocked by the native engine while open',
      () async {
    final box = await DxtrBox.open('active');

    await expectLater(
      DxtrBox.init(path: '/tmp/dxtr_box_other'),
      throwsStateError,
    );

    await box.close();
    await DxtrBox.init(path: '/tmp/dxtr_box_other');
    expect(api.lastInitPath, endsWith('/tmp/dxtr_box_other'));
  });

  test('DxtrBox rejects Windows-unsafe box names on every platform', () async {
    for (final name in <String>[
      '',
      '.',
      '..',
      'nested/box',
      r'nested\box',
      'bad:name',
      'trailing.',
      'trailing ',
      'CON',
      'con.txt',
      'LPT9',
    ]) {
      await expectLater(DxtrBox.open(name), throwsArgumentError);
    }
  });

  test('deleteBox rejects open handles and succeeds after close', () async {
    final box = await DxtrBox.open('temporary');
    expect(await DxtrBox.boxExists('temporary'), isTrue);

    await expectLater(DxtrBox.deleteBox('temporary'), throwsStateError);
    expect(await DxtrBox.boxExists('temporary'), isTrue);

    await box.close();
    await DxtrBox.deleteBox('temporary');
    expect(await DxtrBox.boxExists('temporary'), isFalse);
  });
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

final class _FakeNativeDxtrApi implements NativeDxtrApi {
  final Map<String, Map<String, Uint8List>> _boxes =
      <String, Map<String, Uint8List>>{};
  final Map<String, int> _openCounts = <String, int>{};
  int closeCalls = 0;
  String? lastInitPath;
  Completer<void>? _closeBarrier;

  void seed(String boxName, Map<String, Uint8List> values) {
    _boxes[boxName] = Map<String, Uint8List>.from(values);
  }

  void pauseClose() {
    _closeBarrier = Completer<void>();
  }

  void resumeClose() {
    _closeBarrier?.complete();
    _closeBarrier = null;
  }

  Map<String, Uint8List> _box(String name) =>
      _boxes.putIfAbsent(name, () => <String, Uint8List>{});

  void _requireOpen(String name) {
    if ((_openCounts[name] ?? 0) == 0) {
      throw StateError('box is not open: $name');
    }
  }

  @override
  Future<void> initDb(String path) async {
    if (lastInitPath != null &&
        lastInitPath != path &&
        _openCounts.isNotEmpty) {
      throw StateError('cannot change base path while boxes are open');
    }
    lastInitPath = path;
  }

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async {
    _box(name);
    _openCounts[name] = (_openCounts[name] ?? 0) + 1;
  }

  @override
  Future<void> closeBox(String name) async {
    closeCalls += 1;
    final barrier = _closeBarrier;
    if (barrier != null) await barrier.future;

    final remaining = (_openCounts[name] ?? 1) - 1;
    if (remaining == 0) {
      _openCounts.remove(name);
    } else {
      _openCounts[name] = remaining;
    }
  }

  @override
  Future<void> deleteBox(String name) async {
    if ((_openCounts[name] ?? 0) > 0) {
      throw StateError('cannot delete open box');
    }
    _boxes.remove(name);
  }

  @override
  Future<bool> boxExists(String name) async => _boxes.containsKey(name);

  @override
  Future<void> put(String boxName, String key, Uint8List value) async {
    _requireOpen(boxName);
    _box(boxName)[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> putAll(String boxName, Map<String, Uint8List> values) async {
    _requireOpen(boxName);
    _box(boxName).addAll(
      values.map(
        (key, value) =>
            MapEntry<String, Uint8List>(key, Uint8List.fromList(value)),
      ),
    );
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
  }

  @override
  Future<void> clear(String boxName) async {
    _requireOpen(boxName);
    _box(boxName).clear();
  }

  @override
  Future<List<String>> getAllKeys(String boxName) async {
    _requireOpen(boxName);
    return _box(boxName).keys.toList(growable: false);
  }

  @override
  Future<int> length(String boxName) async {
    _requireOpen(boxName);
    return _box(boxName).length;
  }
}
