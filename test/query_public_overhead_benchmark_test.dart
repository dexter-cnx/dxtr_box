import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/codec.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 250;
const _defaultSamples = 5;
const _warmupIterations = 25;
const _recordCount = 100;

void main() {
  final enabled =
      Platform.environment['DXTR_BOX_QUERY_PUBLIC_OVERHEAD_BENCHMARK'] == '1';
  final iterations = _envInt(
    'DXTR_BOX_QUERY_PUBLIC_OVERHEAD_ITERATIONS',
    _defaultIterations,
  );
  final samples = _envInt(
    'DXTR_BOX_QUERY_PUBLIC_OVERHEAD_SAMPLES',
    _defaultSamples,
  );

  test(
    'public query overhead decomposition executes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_query_public_overhead_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      const api = FrbNativeBoxApi();
      DxtrBox.bindNativeApi(api);
      await DxtrBox.init(path: root.path);
      final box = await DxtrBox.open('query_public_overhead');

      await box.putAll(<String, dynamic>{
        for (var i = 0; i < _recordCount; i++)
          'record-$i': <String, dynamic>{
            'id': i,
            'group': i % 10,
            'name': 'record-$i',
            'active': i.isEven,
          },
      });

      final query = BoxQuery(
        where: QueryComparison(
          field: 'group',
          operator: QueryOperator.equal,
          value: 3,
        ),
        limit: 10,
      );
      final prebuiltWire = _queryWireForBenchmark(query);
      final preencodedPayload = BoxCodec.encode(prebuiltWire);
      final queryApi = api as NativeQueryApi;

      _emit(<String, Object>{
        'kind': 'context',
        'layer': 'query_public_overhead',
        'os': Platform.operatingSystem,
        'dart_version': Platform.version,
        'processors': Platform.numberOfProcessors,
        'iterations': iterations,
        'samples': samples,
        'records': _recordCount,
      });

      Object? sink;

      _measureSync(
        operation: 'query_wire_build_only',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = _queryWireForBenchmark(query);
        },
      );
      expect(sink, isA<Map<String, dynamic>>());

      _measureSync(
        operation: 'query_wire_encode_prebuilt',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = BoxCodec.encode(prebuiltWire);
        },
      );

      _measureSync(
        operation: 'query_wire_build_and_encode',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = BoxCodec.encode(_queryWireForBenchmark(query));
        },
      );

      await _measureAsync(
        operation: 'native_adapter_query_preencoded',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await queryApi.scanQuery(box.name, preencodedPayload);
        },
      );
      expect(sink, isA<List<NativeQueryRecord>>());

      await _measureAsync(
        operation: 'native_adapter_query_build_encode',
        iterations: iterations,
        samples: samples,
        action: () async {
          final payload = BoxCodec.encode(_queryWireForBenchmark(query));
          sink = await queryApi.scanQuery(box.name, payload);
        },
      );

      await _measureAsync(
        operation: 'public_box_query',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box.query(query);
        },
      );
      expect(sink, isA<List<MapEntry<String, dynamic>>>());

      await box.close();
      await DxtrBox.deleteBox('query_public_overhead');
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_QUERY_PUBLIC_OVERHEAD_BENCHMARK=1 to run.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Map<String, dynamic> _queryWireForBenchmark(BoxQuery query) =>
    <String, dynamic>{
      'where': _filterWireForBenchmark(query.where),
      'sortBy': query.sortBy
          .map(
            (sort) => <String, dynamic>{
              'field': sort.field,
              'direction': sort.direction.name,
              'nulls': sort.nulls.name,
            },
          )
          .toList(growable: false),
      'limit': query.limit,
      'offset': query.offset,
    };

Map<String, dynamic> _filterWireForBenchmark(QueryFilter filter) {
  return switch (filter) {
    QueryComparison comparison => <String, dynamic>{
      'type': 'comparison',
      'field': comparison.field,
      'operator': comparison.operator.name,
      'value': comparison.value,
      'upperValue': comparison.upperValue,
    },
    QueryGroup group => <String, dynamic>{
      'type': 'group',
      'operator': group.operator.name,
      'filters': group.filters
          .map(_filterWireForBenchmark)
          .toList(growable: false),
    },
  };
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

  _emitMeasurement(
    operation: operation,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

void _measureSync({
  required String operation,
  required int iterations,
  required int samples,
  required void Function() action,
}) {
  for (var i = 0; i < _warmupIterations; i++) {
    action();
  }

  final sampleNs = <int>[];
  for (var sample = 0; sample < samples; sample++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      action();
    }
    watch.stop();
    sampleNs.add(watch.elapsedMicroseconds * 1000);
  }
  sampleNs.sort();

  _emitMeasurement(
    operation: operation,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

void _emitMeasurement({
  required String operation,
  required int iterations,
  required int samples,
  required List<int> sampleNs,
}) {
  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': 'query_public_overhead',
    'operation': operation,
    'iterations': iterations,
    'samples': samples,
    'sample_ns': sampleNs,
    'median_ns_per_op': _median(sampleNs) / iterations,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_QUERY_PUBLIC_OVERHEAD $line');
  final outputPath =
      Platform.environment['DXTR_BOX_QUERY_PUBLIC_OVERHEAD_OUTPUT'];
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
