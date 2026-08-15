import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nativeEnabled = Platform.environment['DXTR_BOX_NATIVE_TEST'] == '1';

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
      expect(await DxtrBox.boxExists('native'), isTrue);

      final timestamp = DateTime.utc(2026, 8, 15, 5, 30, 45, 123);
      final bytes = Uint8List.fromList(<int>[0, 1, 2, 127, 128, 255]);

      await box.put('int', 42);
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
      expect(box.keys.toSet(), containsAll(<String>{
        'int',
        'string',
        'bytes',
        'time',
        'bool',
        'double',
        'list',
        'map',
      }));

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
    skip: nativeEnabled ? false : 'Set DXTR_BOX_NATIVE_TEST=1 to run native IO.',
  );
}
