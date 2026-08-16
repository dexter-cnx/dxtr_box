import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultSizes = <int>[100, 1000, 5000];
const _defaultSamples = 3;
const _minimumDatasetSize = 19;

void main() {
  final enabled = Platform.environment['DXTR_BOX_QUERY_BENCHMARK'] == '1';
  final sizes = _parseSizes(
    Platform.environment['DXTR_BOX_QUERY_BENCHMARK_SIZES'],
  );
  final samples = int.tryParse(
        Platform.environment['DXTR_BOX_QUERY_BENCHMARK_SAMPLES'] ?? '',
      ) ??
      _defaultSamples;

  test(
    'query/index benchmark scenarios execute',
    () async {
      expect(sizes, isNotEmpty);
      expect(
        sizes,
        everyElement(greaterThanOrEqualTo(_minimumDatasetSize)),
        reason: 'Every query benchmark dataset must contain at least '
            '$_minimumDatasetSize records so range scenarios are non-empty.',
      );
      expect(samples, greaterThan(0));

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_query_benchmark_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      await DxtrBox.init(path: root.path);

      final results = <Map<String, Object>>[];
      for (final size in sizes) {
        for (final scenario in _Scenario.values) {
          final scan = await _measure(
            size: size,
            scenario: scenario,
            indexed: false,
            samples: samples,
          );
          final indexed = await _measure(
            size: size,
            scenario: scenario,
            indexed: true,
            samples: samples,
          );
          results
            ..add(_result(size, scenario, 'scan', scan))
            ..add(_result(size, scenario, 'indexed', indexed));
        }
      }

      for (final result in results) {
        // Timing is diagnostic only. Shared-runner numbers are intentionally
        // not used as a pass/fail regression threshold.
        // ignore: avoid_print
        print('DXTR_BOX_QUERY_BENCHMARK ${jsonEncode(result)}');
      }

      expect(results, hasLength(sizes.length * _Scenario.values.length * 2));
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_QUERY_BENCHMARK=1 to run query/index benchmarks.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

enum _Scenario { equality, range, andIntersection, sortedRange }

List<int> _parseSizes(String? raw) {
  if (raw == null || raw.trim().isEmpty) return _defaultSizes;
  final parsed = raw
      .split(',')
      .map((value) => int.tryParse(value.trim()))
      .whereType<int>()
      .where((value) => value > 0)
      .toList(growable: false);
  return parsed.isEmpty ? _defaultSizes : parsed;
}

Future<List<int>> _measure({
  required int size,
  required _Scenario scenario,
  required bool indexed,
  required int samples,
}) async {
  await _runSample(
    size: size,
    scenario: scenario,
    indexed: indexed,
    sample: 'warmup',
  );

  final values = <int>[];
  for (var i = 0; i < samples; i++) {
    values.add(
      await _runSample(
        size: size,
        scenario: scenario,
        indexed: indexed,
        sample: 'sample_$i',
      ),
    );
  }
  return values;
}

Future<int> _runSample({
  required int size,
  required _Scenario scenario,
  required bool indexed,
  required String sample,
}) async {
  final mode = indexed ? 'indexed' : 'scan';
  final boxName = 'query_bench_${scenario.name}_${size}_${mode}_$sample';
  final box = await DxtrBox.open(boxName);

  await box.putAll(<String, dynamic>{
    for (var i = 0; i < size; i++)
      'k${i.toString().padLeft(8, '0')}': <String, dynamic>{
        'status': i % 3 == 0 ? 'active' : 'inactive',
        'profile': <String, dynamic>{'age': i % 101, 'score': i},
      },
  });

  if (indexed) {
    switch (scenario) {
      case _Scenario.equality:
        await box.createIndex(
          IndexDefinition(name: 'by-status', field: 'status'),
        );
      case _Scenario.range:
      case _Scenario.sortedRange:
        await box.createIndex(
          IndexDefinition(name: 'by-age', field: 'profile.age'),
        );
      case _Scenario.andIntersection:
        await box.createIndex(
          IndexDefinition(name: 'by-status', field: 'status'),
        );
        await box.createIndex(
          IndexDefinition(name: 'by-age', field: 'profile.age'),
        );
    }
  }

  final query = switch (scenario) {
    _Scenario.equality => BoxQuery(
        where: QueryComparison(
          field: 'status',
          operator: QueryOperator.equal,
          value: 'active',
        ),
      ),
    _Scenario.range => BoxQuery(
        where: QueryComparison(
          field: 'profile.age',
          operator: QueryOperator.between,
          value: 18,
          upperValue: 45,
        ),
      ),
    _Scenario.andIntersection => BoxQuery(
        where: QueryGroup.and(<QueryFilter>[
          QueryComparison(
            field: 'status',
            operator: QueryOperator.equal,
            value: 'active',
          ),
          QueryComparison(
            field: 'profile.age',
            operator: QueryOperator.greaterThanOrEqual,
            value: 18,
          ),
        ]),
      ),
    _Scenario.sortedRange => BoxQuery(
        where: QueryComparison(
          field: 'profile.age',
          operator: QueryOperator.between,
          value: 18,
          upperValue: 45,
        ),
        sortBy: <QuerySort>[
          QuerySort(
            field: 'profile.score',
            direction: QuerySortDirection.descending,
          ),
        ],
        limit: 50,
      ),
  };

  final watch = Stopwatch()..start();
  final rows = await box.query(query);
  watch.stop();

  expect(rows, isNotEmpty);
  await box.close();
  await DxtrBox.deleteBox(boxName);
  return watch.elapsedMicroseconds;
}

Map<String, Object> _result(
  int size,
  _Scenario scenario,
  String execution,
  List<int> samples,
) {
  final ordered = List<int>.from(samples)..sort();
  return <String, Object>{
    'dataset_size': size,
    'scenario': scenario.name,
    'execution': execution,
    'samples_us': samples,
    'median_us': _medianMicros(ordered),
    'min_us': ordered.first,
    'max_us': ordered.last,
  };
}

num _medianMicros(List<int> ordered) {
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}
