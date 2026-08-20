import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 200;
const _defaultSamples = 5;
const _defaultRecords = 1000;
const _warmupIterations = 20;

void main() {
  final enabled =
      Platform.environment['DXTR_BOX_MULTI_FRONTEND_BENCHMARK'] == '1';
  final iterations = _envInt(
    'DXTR_BOX_MULTI_FRONTEND_DART_ITERATIONS',
    _defaultIterations,
  );
  final samples = _envInt(
    'DXTR_BOX_MULTI_FRONTEND_DART_SAMPLES',
    _defaultSamples,
  );
  final records = _envInt(
    'DXTR_BOX_MULTI_FRONTEND_RECORDS',
    _defaultRecords,
  );

  test(
    '0.8 Dart FRB multi-frontend diagnostic matrix executes',
    () async {
      expect(iterations, greaterThan(0));
      expect(samples, greaterThan(0));
      expect(records, greaterThanOrEqualTo(100));

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_multi_frontend_benchmark_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      await BoxStore.init(path: root.path);
      final box = await BoxStore.open('multi_frontend');
      final entries = <String, dynamic>{};
      for (var index = 0; index < records; index++) {
        entries['item-${index.toString().padLeft(5, '0')}'] = <String, dynamic>{
          'score': index,
          'group': index % 4 == 0 ? 'target' : 'other',
          'payload': 'x' * 128,
        };
      }
      await box.putAll(entries);
      await box.createIndex(name: 'by_group', field: 'group');

      final pointKey = 'item-${(records ~/ 2).toString().padLeft(5, '0')}';
      final batchKeys = List<String>.generate(
        records < 100 ? records : 100,
        (index) => 'item-${index.toString().padLeft(5, '0')}',
      );

      _emit(<String, Object>{
        'kind': 'context',
        'frontend': 'dart-frb',
        'os': Platform.operatingSystem,
        'dart_version': Platform.version,
        'processors': Platform.numberOfProcessors,
        'iterations': iterations,
        'samples': samples,
        'records': records,
      });

      Object? sink;
      await _measureAsync(
        operation: 'get',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box.get(pointKey);
        },
      );
      expect(sink, isA<Map<dynamic, dynamic>>());

      await _measureAsync(
        operation: 'get_all_100',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box.getAll(batchKeys);
        },
      );
      expect(sink, isA<List<MapEntry<String, dynamic>>>());

      await _measureAsync(
        operation: 'indexed_query_sort_limit',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box
              .queryWhere('group')
              .equals('target')
              .orderBy('score', descending: true)
              .limit(50)
              .find();
        },
      );
      expect(sink, isA<List<MapEntry<String, dynamic>>>());

      await box.close();
      await BoxStore.deleteBox('multi_frontend');
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_MULTI_FRONTEND_BENCHMARK=1 to run 0.8 diagnostics.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _measureAsync({
  required String operation,
  required int iterations,
  required int samples,
  required Future<void> Function() action,
}) async {
  for (var i = 0; i < _warmupIterations; i++) {
    await action();
  }

  final sampleNs = <int>[];
  for (var sample = 0; sample < samples; sample++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await action();
    }
    watch.stop();
    sampleNs.add(watch.elapsedMicroseconds * 1000);
  }
  sampleNs.sort();
  final medianTotalNs = _median(sampleNs);
  _emit(<String, Object>{
    'kind': 'measurement',
    'frontend': 'dart-frb',
    'operation': operation,
    'iterations': iterations,
    'samples': samples,
    'sample_ns': sampleNs,
    'median_ns_per_op': medianTotalNs / iterations,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_MULTI_FRONTEND_DART $line');
  final outputPath =
      Platform.environment['DXTR_BOX_MULTI_FRONTEND_DART_OUTPUT'];
  if (outputPath == null || outputPath.isEmpty) return;
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

int _envInt(String name, int fallback) =>
    int.tryParse(Platform.environment[name] ?? '') ?? fallback;

num _median(List<int> ordered) {
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}
