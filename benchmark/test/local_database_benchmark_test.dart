import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dxtr_box_benchmark/local_database_adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart' as hive;

const _defaultOperations = 200;
const _samples = 3;

void main() {
  final enabled = Platform.environment['DXTR_BOX_COMPARISON_BENCHMARK'] == '1';
  final operations = int.tryParse(
        Platform.environment['DXTR_BOX_COMPARISON_OPS'] ?? '',
      ) ??
      _defaultOperations;

  test(
    'broader Flutter local database diagnostic matrix executes',
    () async {
      expect(operations, greaterThan(0));

      final root = await Directory.systemTemp.createTemp('dxtr_box_matrix_');
      final dxtrRoot = Directory('${root.path}/dxtr')
        ..createSync(recursive: true);
      final hiveRoot = Directory('${root.path}/hive')
        ..createSync(recursive: true);

      await initializeComparisonBackends(
        dxtrRoot: dxtrRoot,
        hiveRoot: hiveRoot,
      );

      try {
        final results = <Map<String, Object>>[];
        for (final scenario in <String>[
          'sequential_put',
          'batch_put',
          'point_get',
          'contains',
          'delete_all',
          'reopen_read',
        ]) {
          final samplesByEngine = <String, List<int>>{};

          for (var sample = -1; sample < _samples; sample++) {
            final sampleOperations =
                sample < 0 ? math.max(10, operations ~/ 10) : operations;
            final adapters = createComparisonAdapters(
              root: root,
              suffix: '${scenario}_${sample < 0 ? 'warmup' : sample}',
            );

            for (final adapter in adapters) {
              final elapsed = await _runScenario(
                adapter,
                scenario,
                sampleOperations,
              );
              if (sample >= 0) {
                samplesByEngine
                    .putIfAbsent(adapter.engine, () => <int>[])
                    .add(elapsed);
              }
            }
          }

          for (final entry in samplesByEngine.entries) {
            results.add(
              _result(entry.key, scenario, operations, entry.value),
            );
          }
        }

        for (final result in results) {
          // Machine-readable diagnostic evidence. There are intentionally no
          // faster/slower assertions: correctness is enforced separately.
          // ignore: avoid_print
          print('DXTR_BOX_COMPARISON ${jsonEncode(result)}');
        }

        expect(results, hasLength(24));
      } finally {
        await hive.Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      }
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_COMPARISON_BENCHMARK=1 to run diagnostic matrix.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<int> _runScenario(
  LocalDatabaseAdapter adapter,
  String scenario,
  int operations,
) async {
  await adapter.open();

  Future<void> populate() => adapter.putAll(<String, ComparisonPayload>{
        for (var i = 0; i < operations; i++) 'k$i': comparisonPayload(i),
      });

  if (scenario == 'point_get' ||
      scenario == 'contains' ||
      scenario == 'delete_all' ||
      scenario == 'reopen_read') {
    await populate();
  }

  if (scenario == 'reopen_read') {
    await adapter.close();
  }

  final watch = Stopwatch()..start();
  switch (scenario) {
    case 'sequential_put':
      for (var i = 0; i < operations; i++) {
        await adapter.put('k$i', comparisonPayload(i));
      }
      break;
    case 'batch_put':
      await adapter.putAll(<String, ComparisonPayload>{
        for (var i = 0; i < operations; i++) 'k$i': comparisonPayload(i),
      });
      break;
    case 'point_get':
      for (var i = 0; i < operations; i++) {
        await adapter.get('k$i');
      }
      break;
    case 'contains':
      for (var i = 0; i < operations; i++) {
        await adapter.containsKey('k$i');
      }
      break;
    case 'delete_all':
      await adapter.deleteAll(<String>[
        for (var i = 0; i < operations; i++) 'k$i',
      ]);
      break;
    case 'reopen_read':
      await adapter.open();
      for (var i = 0; i < operations; i++) {
        await adapter.get('k$i');
      }
      break;
    default:
      throw ArgumentError.value(scenario, 'scenario');
  }
  watch.stop();

  await adapter.destroy();
  return watch.elapsedMicroseconds;
}

Map<String, Object> _result(
  String engine,
  String scenario,
  int operations,
  List<int> samples,
) {
  final ordered = List<int>.from(samples)..sort();
  return <String, Object>{
    'engine': engine,
    'scenario': scenario,
    'operations': operations,
    'samples': samples,
    'median_us': ordered[ordered.length ~/ 2],
    'min_us': ordered.first,
    'max_us': ordered.last,
  };
}
