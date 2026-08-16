import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart' as hive;

void main() {
  final nativeEnabled = Platform.environment['DXTR_BOX_NATIVE_TEST'] == '1';

  test(
    'migrates real Hive CE values and preserves the source',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_hive_migrate_');
      final hiveRoot = Directory('${root.path}/hive')..createSync();
      final dxtrRoot = Directory('${root.path}/dxtr')..createSync();
      addTearDown(() async {
        await hive.Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      hive.Hive.init(hiveRoot.path);
      final source = await hive.Hive.openBox<dynamic>('legacy');
      final timestamp = DateTime.utc(2026, 8, 16, 1, 2, 3, 456);
      final bytes = Uint8List.fromList(<int>[0, 1, 127, 128, 255]);
      await source.putAll(<dynamic, dynamic>{
        'null': null,
        'bool': true,
        'int': 42,
        'double': 3.5,
        'string': 'legacy',
        'bytes': bytes,
        'time': timestamp,
        'list': <dynamic>[1, 'two', false],
        'map': <String, dynamic>{'nested': 7},
        7: 'integer-key',
        'big': BigInt.parse('123456789012345678901234567890'),
      });

      await DxtrBox.init(path: dxtrRoot.path);
      final result = await migrateFromHiveCe(
        source,
        destinationName: 'imported',
        valueConverter: (value) {
          if (value is BigInt) {
            return <String, dynamic>{
              'type': 'BigInt',
              'value': value.toString(),
            };
          }
          throw UnsupportedError('No converter for ${value.runtimeType}');
        },
      );

      expect(result.sourceName, 'legacy');
      expect(result.destinationName, 'imported');
      expect(result.entriesMigrated, 11);
      expect(source.isOpen, isTrue);
      expect(source.get('string'), 'legacy');
      expect(source.get(7), 'integer-key');

      final destination = await DxtrBox.open('imported');
      expect(await destination.get('null'), isNull);
      expect(await destination.get('bool'), isTrue);
      expect(await destination.get('int'), 42);
      expect(await destination.get('double'), 3.5);
      expect(await destination.get('string'), 'legacy');
      expect(await destination.get('bytes'), orderedEquals(bytes));
      expect(await destination.get('time'), timestamp);
      expect(await destination.get('list'), <dynamic>[1, 'two', false]);
      expect(await destination.get('map'), <String, dynamic>{'nested': 7});
      expect(await destination.get('@hive-int:7'), 'integer-key');
      expect(await destination.get('big'), <String, dynamic>{
        'type': 'BigInt',
        'value': '123456789012345678901234567890',
      });
      await destination.close();
    },
    skip: nativeEnabled
        ? false
        : 'Set DXTR_BOX_NATIVE_TEST=1 to run Hive CE migration IO.',
  );

  test(
    'rejects converted-key collisions before creating destination',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_hive_collision_');
      final hiveRoot = Directory('${root.path}/hive')..createSync();
      final dxtrRoot = Directory('${root.path}/dxtr')..createSync();
      addTearDown(() async {
        await hive.Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      hive.Hive.init(hiveRoot.path);
      final source = await hive.Hive.openBox<dynamic>('collision');
      await source.put('@hive-int:1', 'string-key');
      await source.put(1, 'integer-key');

      await DxtrBox.init(path: dxtrRoot.path);
      await expectLater(
        migrateFromHiveCe(source, destinationName: 'must-not-exist'),
        throwsStateError,
      );
      expect(await DxtrBox.boxExists('must-not-exist'), isFalse);
      expect(source.get('@hive-int:1'), 'string-key');
      expect(source.get(1), 'integer-key');
    },
    skip: nativeEnabled
        ? false
        : 'Set DXTR_BOX_NATIVE_TEST=1 to run Hive CE migration IO.',
  );

  test(
    'migrates an encrypted Hive CE source into encrypted dxtr_box',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_hive_encrypted_');
      final hiveRoot = Directory('${root.path}/hive')..createSync();
      final dxtrRoot = Directory('${root.path}/dxtr')..createSync();
      addTearDown(() async {
        await hive.Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      hive.Hive.init(hiveRoot.path);
      final hiveKey = List<int>.generate(32, (index) => index);
      final source = await hive.Hive.openBox<dynamic>(
        'secure_legacy',
        encryptionCipher: hive.HiveAesCipher(hiveKey),
      );
      await source.put('token', <String, dynamic>{'value': 'secret'});

      await DxtrBox.init(path: dxtrRoot.path);
      await migrateFromHiveCe(
        source,
        destinationName: 'secure_import',
        destinationEncryptionKey: 'dxtr-migration-key',
      );

      await expectLater(
        DxtrBox.open('secure_import'),
        throwsA(isA<Object>()),
      );
      final destination = await DxtrBox.open(
        'secure_import',
        encryptionKey: 'dxtr-migration-key',
      );
      expect(await destination.get('token'), <String, dynamic>{
        'value': 'secret',
      });
      await destination.close();

      expect(source.isOpen, isTrue);
      expect(source.get('token'), <String, dynamic>{'value': 'secret'});
    },
    skip: nativeEnabled
        ? false
        : 'Set DXTR_BOX_NATIVE_TEST=1 to run Hive CE migration IO.',
  );
}
