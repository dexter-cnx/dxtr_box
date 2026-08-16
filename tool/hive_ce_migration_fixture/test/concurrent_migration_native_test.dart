import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart' as hive;

HiveCeMigrationSource _source(hive.Box<dynamic> box) {
  return HiveCeMigrationSource(
    name: box.name,
    isOpen: () => box.isOpen,
    keys: () => box.keys,
    get: box.get,
  );
}

Future<Object> _capture(Future<HiveCeMigrationResult> future) async {
  try {
    return await future;
  } catch (error) {
    return error;
  }
}

void main() {
  final nativeEnabled = Platform.environment['DXTR_BOX_NATIVE_TEST'] == '1';

  test(
    'concurrent migrations cannot share one new destination',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_hive_race_');
      final hiveRoot = Directory('${root.path}/hive')..createSync();
      final dxtrRoot = Directory('${root.path}/dxtr')..createSync();
      addTearDown(() async {
        await hive.Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      hive.Hive.init(hiveRoot.path);
      final sourceBox = await hive.Hive.openBox<dynamic>('race_source');
      await sourceBox.putAll(<dynamic, dynamic>{
        'one': 1,
        'two': 2,
      });

      await DxtrBox.init(path: dxtrRoot.path);
      final results = await Future.wait<Object>(<Future<Object>>[
        _capture(
          migrateFromHiveCe(
            _source(sourceBox),
            destinationName: 'race_destination',
          ),
        ),
        _capture(
          migrateFromHiveCe(
            _source(sourceBox),
            destinationName: 'race_destination',
          ),
        ),
      ]);

      expect(results.whereType<HiveCeMigrationResult>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));

      final destination = await DxtrBox.open('race_destination');
      expect(await destination.get('one'), 1);
      expect(await destination.get('two'), 2);
      expect(destination.length, 2);
      await destination.close();

      expect(sourceBox.get('one'), 1);
      expect(sourceBox.get('two'), 2);
    },
    skip: nativeEnabled
        ? false
        : 'Set DXTR_BOX_NATIVE_TEST=1 to run Hive CE migration IO.',
  );
}
