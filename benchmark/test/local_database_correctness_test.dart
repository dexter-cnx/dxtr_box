import 'dart:io';

import 'package:dxtr_box_benchmark/local_database_adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart' as hive;

void main() {
  final enabled = Platform.environment['DXTR_BOX_COMPARISON'] == '1';

  test(
    'local database adapters preserve the same CRUD and reopen semantics',
    () async {
      final root = await Directory.systemTemp.createTemp('dxtr_box_compare_');
      final dxtrRoot = Directory('${root.path}/dxtr')
        ..createSync(recursive: true);
      final hiveRoot = Directory('${root.path}/hive')
        ..createSync(recursive: true);

      await initializeComparisonBackends(
        dxtrRoot: dxtrRoot,
        hiveRoot: hiveRoot,
      );

      final adapters = createComparisonAdapters(
        root: root,
        suffix: 'correctness',
      );

      try {
        Map<String, ComparisonPayload>? reference;

        for (final adapter in adapters) {
          await adapter.open();
          await adapter.putAll(<String, ComparisonPayload>{
            for (var i = 0; i < 40; i++) 'k$i': comparisonPayload(i),
          });

          await adapter.put(
            'k3',
            <String, Object?>{
              ...comparisonPayload(3),
              'name': 'updated-3',
            },
          );

          expect(await adapter.containsKey('k3'), isTrue,
              reason: '${adapter.engine} should contain k3');
          expect(await adapter.containsKey('missing'), isFalse,
              reason: '${adapter.engine} should not contain missing');
          expect((await adapter.get('k3'))?['name'], 'updated-3',
              reason: '${adapter.engine} should expose overwritten values');

          await adapter.deleteAll(<String>[
            for (var i = 0; i < 40; i += 2) 'k$i',
          ]);

          await adapter.close();
          await adapter.open();

          final snapshot = <String, ComparisonPayload>{};
          for (var i = 0; i < 40; i++) {
            final value = await adapter.get('k$i');
            if (i.isEven) {
              expect(value, isNull,
                  reason: '${adapter.engine} should persist deletion of k$i');
            } else {
              expect(value, isNotNull,
                  reason: '${adapter.engine} should persist k$i after reopen');
              snapshot['k$i'] = value!;
            }
          }

          reference ??= snapshot;
          expect(
            snapshot,
            reference,
            reason:
                '${adapter.engine} must match the canonical cross-engine snapshot',
          );
        }
      } finally {
        for (final adapter in adapters) {
          await adapter.destroy();
        }
        await hive.Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      }
    },
    skip: enabled ? false : 'Set DXTR_BOX_COMPARISON=1 to run comparison gate.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
