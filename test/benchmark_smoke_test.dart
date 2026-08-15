import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _defaultOperations = 200;
const _samples = 5;

void main() {
  final enabled = Platform.environment['DXTR_BOX_BENCHMARK'] == '1';
  final operations = int.tryParse(
        Platform.environment['DXTR_BOX_BENCHMARK_OPS'] ?? '',
      ) ??
      _defaultOperations;

  test(
    'dxtr_box and hive_ce benchmark smoke workloads execute',
    () async {
      expect(operations, greaterThan(0));
      final root = await Directory.systemTemp.createTemp('dxtr_box_benchmark_');
      addTearDown(() async {
        await Hive.close();
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      final dxtrRoot = Directory('${root.path}/dxtr')
        ..createSync(recursive: true);
      final hiveRoot = Directory('${root.path}/hive')
        ..createSync(recursive: true);

      await DxtrBox.init(path: dxtrRoot.path);
      Hive.init(hiveRoot.path);

      final results = <Map<String, Object>>[];
      for (final scenario in <String>[
        'sequential_put',
        'batch_put',
        'point_get',
        'contains',
        'delete_all',
        'reopen_read',
      ]) {
        final dxtr = await _measureDxtr(scenario, operations);
        final hive = await _measureHive(scenario, operations);
        results
          ..add(_result('dxtr_box', scenario, operations, dxtr))
          ..add(_result('hive_ce', scenario, operations, hive));
      }

      for (final result in results) {
        // Machine-readable prefix for CI artifacts and later report tooling.
        // Timing values are informational only; this test asserts execution,
        // not that either database is faster than the other.
        // ignore: avoid_print
        print('DXTR_BOX_BENCHMARK ${jsonEncode(result)}');
      }

      expect(results, hasLength(12));
    },
    skip: enabled ? false : 'Set DXTR_BOX_BENCHMARK=1 to run benchmark smoke.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Map<String, Object> _result(
  String engine,
  String scenario,
  int operations,
  List<int> samples,
) {
  final ordered = List<int>.from(samples)..sort();
  final median = ordered[ordered.length ~/ 2];
  return <String, Object>{
    'engine': engine,
    'scenario': scenario,
    'operations': operations,
    'samples': samples,
    'median_us': median,
    'min_us': ordered.first,
    'max_us': ordered.last,
  };
}

Future<List<int>> _measureDxtr(String scenario, int operations) async {
  await _runDxtrScenario(
    'warmup_$scenario',
    scenario,
    math.max(10, operations ~/ 10),
  );
  final samples = <int>[];
  for (var sample = 0; sample < _samples; sample++) {
    samples.add(
      await _runDxtrScenario(
        'sample_${sample}_$scenario',
        scenario,
        operations,
      ),
    );
  }
  return samples;
}

Future<int> _runDxtrScenario(
  String name,
  String scenario,
  int operations,
) async {
  final boxName = 'bench_dxtr_$name';
  var box = await DxtrBox.open(boxName);

  Future<void> populate() async {
    await box.putAll(<String, dynamic>{
      for (var i = 0; i < operations; i++) 'k$i': _payload(i),
    });
  }

  if (scenario == 'point_get' ||
      scenario == 'contains' ||
      scenario == 'delete_all' ||
      scenario == 'reopen_read') {
    await populate();
  }

  if (scenario == 'reopen_read') {
    await box.close();
  }

  final watch = Stopwatch()..start();
  switch (scenario) {
    case 'sequential_put':
      for (var i = 0; i < operations; i++) {
        await box.put('k$i', _payload(i));
      }
      break;
    case 'batch_put':
      await box.putAll(<String, dynamic>{
        for (var i = 0; i < operations; i++) 'k$i': _payload(i),
      });
      break;
    case 'point_get':
      for (var i = 0; i < operations; i++) {
        await box.get('k$i');
      }
      break;
    case 'contains':
      for (var i = 0; i < operations; i++) {
        await box.containsKey('k$i');
      }
      break;
    case 'delete_all':
      await box.deleteAll(<String>[
        for (var i = 0; i < operations; i++) 'k$i',
      ]);
      break;
    case 'reopen_read':
      box = await DxtrBox.open(boxName);
      for (var i = 0; i < operations; i++) {
        await box.get('k$i');
      }
      break;
    default:
      throw ArgumentError.value(scenario, 'scenario');
  }
  watch.stop();

  await box.close();
  await DxtrBox.deleteBox(boxName);
  return watch.elapsedMicroseconds;
}

Future<List<int>> _measureHive(String scenario, int operations) async {
  await _runHiveScenario(
    'warmup_$scenario',
    scenario,
    math.max(10, operations ~/ 10),
  );
  final samples = <int>[];
  for (var sample = 0; sample < _samples; sample++) {
    samples.add(
      await _runHiveScenario(
        'sample_${sample}_$scenario',
        scenario,
        operations,
      ),
    );
  }
  return samples;
}

Future<int> _runHiveScenario(
  String name,
  String scenario,
  int operations,
) async {
  final boxName = 'bench_hive_$name';
  var box = await Hive.openBox<dynamic>(boxName);

  Future<void> populate() async {
    await box.putAll(<String, dynamic>{
      for (var i = 0; i < operations; i++) 'k$i': _payload(i),
    });
  }

  if (scenario == 'point_get' ||
      scenario == 'contains' ||
      scenario == 'delete_all' ||
      scenario == 'reopen_read') {
    await populate();
  }

  if (scenario == 'reopen_read') {
    await box.close();
  }

  final watch = Stopwatch()..start();
  switch (scenario) {
    case 'sequential_put':
      for (var i = 0; i < operations; i++) {
        await box.put('k$i', _payload(i));
      }
      break;
    case 'batch_put':
      await box.putAll(<String, dynamic>{
        for (var i = 0; i < operations; i++) 'k$i': _payload(i),
      });
      break;
    case 'point_get':
      for (var i = 0; i < operations; i++) {
        box.get('k$i');
      }
      break;
    case 'contains':
      for (var i = 0; i < operations; i++) {
        box.containsKey('k$i');
      }
      break;
    case 'delete_all':
      await box.deleteAll(<String>[
        for (var i = 0; i < operations; i++) 'k$i',
      ]);
      break;
    case 'reopen_read':
      box = await Hive.openBox<dynamic>(boxName);
      for (var i = 0; i < operations; i++) {
        box.get('k$i');
      }
      break;
    default:
      throw ArgumentError.value(scenario, 'scenario');
  }
  watch.stop();

  await box.close();
  await Hive.deleteBoxFromDisk(boxName);
  return watch.elapsedMicroseconds;
}

Map<String, dynamic> _payload(int index) => <String, dynamic>{
      'id': index,
      'name': 'item-$index',
      'active': index.isEven,
      'score': index / 10,
    };
