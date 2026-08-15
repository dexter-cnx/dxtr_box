import 'dart:typed_data';

import 'package:dxtr_box/src/box.dart';
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

  test('get returns default value for a missing key', () async {
    final box = await DxtrBox.open('settings');
    expect(await box.get('missing', defaultValue: 'fallback'), 'fallback');
  });

  test('putAll and where operate over decoded values', () async {
    final box = await DxtrBox.open('scores');
    await box.putAll(<String, dynamic>{
      'a': 10,
      'b': 20,
      'c': 30,
    });

    final matches = await box.where((value) => value is int && value >= 20);
    expect(matches.map((entry) => entry.key), orderedEquals(<String>['b', 'c']));
    expect(matches.map((entry) => entry.value), orderedEquals(<int>[20, 30]));
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

  test('DxtrBox rejects unsafe box names', () async {
    for (final name in <String>['', '.', '..', 'nested/box', r'nested\box']) {
      await expectLater(DxtrBox.open(name), throwsArgumentError);
    }
  });

  test('deleteBox and boxExists delegate to native engine', () async {
    await DxtrBox.open('temporary');
    expect(await DxtrBox.boxExists('temporary'), isTrue);

    await DxtrBox.deleteBox('temporary');
    expect(await DxtrBox.boxExists('temporary'), isFalse);
  });
}

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

final class _FakeNativeDxtrApi implements NativeDxtrApi {
  final Map<String, Map<String, Uint8List>> _boxes = <String, Map<String, Uint8List>>{};
  int closeCalls = 0;

  void seed(String boxName, Map<String, Uint8List> values) {
    _boxes[boxName] = Map<String, Uint8List>.from(values);
  }

  Map<String, Uint8List> _box(String name) =>
      _boxes.putIfAbsent(name, () => <String, Uint8List>{});

  @override
  Future<void> initDb(String path) async {}

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async {
    _box(name);
  }

  @override
  Future<void> closeBox(String name) async {
    closeCalls += 1;
  }

  @override
  Future<void> deleteBox(String name) async {
    _boxes.remove(name);
  }

  @override
  Future<bool> boxExists(String name) async => _boxes.containsKey(name);

  @override
  Future<void> put(String boxName, String key, Uint8List value) async {
    _box(boxName)[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> putAll(String boxName, Map<String, Uint8List> values) async {
    _box(boxName).addAll(
      values.map(
        (key, value) => MapEntry<String, Uint8List>(key, Uint8List.fromList(value)),
      ),
    );
  }

  @override
  Future<Uint8List?> get(String boxName, String key) async {
    final value = _box(boxName)[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<bool> containsKey(String boxName, String key) async => _box(boxName).containsKey(key);

  @override
  Future<void> delete(String boxName, String key) async {
    _box(boxName).remove(key);
  }

  @override
  Future<void> clear(String boxName) async {
    _box(boxName).clear();
  }

  @override
  Future<List<String>> getAllKeys(String boxName) async => _box(boxName).keys.toList(growable: false);

  @override
  Future<int> length(String boxName) async => _box(boxName).length;
}
