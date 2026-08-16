import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nativeEnabled = Platform.environment['DXTR_BOX_NATIVE_TEST'] == '1';

  test('native getAll preserves order, duplicates, misses, and encryption',
      () async {
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

  test(
    'Dart -> FRB -> Rust -> redb round trip persists across reopen',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_box_native_');
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      await DxtrBox.init(path: root.path);
      expect(await DxtrBox.boxExists('native'), isFalse);

      var box = await DxtrBox.open('native');
      final observer = await DxtrBox.open('native');
      expect(await DxtrBox.boxExists('native'), isTrue);

      final timestamp = DateTime.utc(2026, 8, 15, 5, 30, 45, 123);
      final bytes = Uint8List.fromList(<int>[0, 1, 2, 127, 128, 255]);

      final observedIntPut = observer.watch(key: 'int').first;
      await box.put('int', 42);
      final nativeWatchEvent = await observedIntPut.timeout(
        const Duration(seconds: 5),
      );
      expect(nativeWatchEvent.type, BoxEventType.put);
      expect(nativeWatchEvent.key, 'int');
      expect(nativeWatchEvent.value, 42);

      await box.put('string', 'forged in Rust');
      await box.put('bytes', bytes);
      await box.put('time', timestamp);
      await box.putAll(<String, dynamic>{
        'bool': true,
        'double': 3.5,
        'list': <dynamic>[1, 'two', false],
        'map': <String, dynamic>{'nested': 7},
      });

      expect(await box.get('int'), 42);
      expect(await box.get('string'), 'forged in Rust');
      expect(await box.get('bytes'), orderedEquals(bytes));
      expect(await box.get('time'), timestamp);
      expect(await box.get('bool'), isTrue);
      expect(await box.get('double'), 3.5);
      expect(await box.get('list'), <dynamic>[1, 'two', false]);
      expect(await box.get('map'), <String, dynamic>{'nested': 7});
      expect(await box.containsKey('int'), isTrue);
      expect(box.length, 8);
      expect(
        box.keys.toSet(),
        containsAll(<String>{
          'int',
          'string',
          'bytes',
          'time',
          'bool',
          'double',
          'list',
          'map',
        }),
      );

      await observer.close();
      await box.close();
      box = await DxtrBox.open('native');
      expect(await box.get('string'), 'forged in Rust');
      expect(box.length, 8);

      await box.delete('int');
      expect(await box.containsKey('int'), isFalse);
      expect(box.length, 7);

      await box.clear();
      expect(box.isEmpty, isTrue);
      await box.close();

      await DxtrBox.deleteBox('native');
      expect(await DxtrBox.boxExists('native'), isFalse);
    },
    skip:
        nativeEnabled ? false : 'Set DXTR_BOX_NATIVE_TEST=1 to run native IO.',
  );

  test(
    'encrypted box persists and rejects missing or wrong keys',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_box_encrypted_');
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      await DxtrBox.init(path: root.path);
      var box = await DxtrBox.open(
        'secure',
        encryptionKey: 'correct horse battery staple',
      );
      await box.put('token', <String, dynamic>{'value': 'secret', 'count': 7});
      expect(await box.get('token'), <String, dynamic>{
        'value': 'secret',
        'count': 7,
      });
      await box.close();

      await expectLater(DxtrBox.open('secure'), throwsA(isA<Object>()));
      await expectLater(
        DxtrBox.open('secure', encryptionKey: 'wrong key'),
        throwsA(isA<Object>()),
      );

      box = await DxtrBox.open(
        'secure',
        encryptionKey: 'correct horse battery staple',
      );
      expect(await box.get('token'), <String, dynamic>{
        'value': 'secret',
        'count': 7,
      });
      await box.close();

      await DxtrBox.deleteBox('secure');
      expect(await DxtrBox.boxExists('secure'), isFalse);
    },
    skip:
        nativeEnabled ? false : 'Set DXTR_BOX_NATIVE_TEST=1 to run native IO.',
  );

  test(
    'plaintext box migrates through public Dart API and preserves data',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_box_migrate_');
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      await DxtrBox.init(path: root.path);
      var box = await DxtrBox.open('migrate');
      await box.put('answer', 42);
      await box.put('profile', <String, dynamic>{
        'name': 'Dxtr',
        'enabled': true,
      });

      await expectLater(
        DxtrBox.encryptBox('migrate', encryptionKey: 'migration-key'),
        throwsStateError,
      );

      await box.close();
      await DxtrBox.encryptBox('migrate', encryptionKey: 'migration-key');

      await expectLater(DxtrBox.open('migrate'), throwsA(isA<Object>()));
      await expectLater(
        DxtrBox.open('migrate', encryptionKey: 'wrong-key'),
        throwsA(isA<Object>()),
      );

      box = await DxtrBox.open('migrate', encryptionKey: 'migration-key');
      expect(await box.get('answer'), 42);
      expect(await box.get('profile'), <String, dynamic>{
        'name': 'Dxtr',
        'enabled': true,
      });
      await box.close();

      await DxtrBox.deleteBox('migrate');
      expect(await DxtrBox.boxExists('migrate'), isFalse);
    },
    skip:
        nativeEnabled ? false : 'Set DXTR_BOX_NATIVE_TEST=1 to run native IO.',
  );
}
