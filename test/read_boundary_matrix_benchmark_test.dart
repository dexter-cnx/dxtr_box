import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/codec.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:dxtr_box/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 250;
const _defaultSamples = 5;
const _warmupIterations = 25;
const _recordCount = 100;

void main() {
  final enabled =
      Platform.environment['DXTR_BOX_READ_BOUNDARY_MATRIX_BENCHMARK'] == '1';
  final iterations = _envInt(
    'DXTR_BOX_READ_BOUNDARY_MATRIX_ITERATIONS',
    _defaultIterations,
  );
  final samples = _envInt(
    'DXTR_BOX_READ_BOUNDARY_MATRIX_SAMPLES',
    _defaultSamples,
  );

  test(
    'FRB read boundary matrix executes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_read_boundary_matrix_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      const api = FrbNativeBoxApi();
      DxtrBox.bindNativeApi(api);
      await DxtrBox.init(path: root.path);
      final box = await DxtrBox.open('read_boundary_matrix');

      final entries = <String, dynamic>{
        for (var i = 0; i < _recordCount; i++)
          'record-$i': <String, dynamic>{
            'id': i,
            'group': i % 10,
            'name': 'record-$i',
            'active': i.isEven,
          },
      };
      await box.putAll(entries);

      final batch10 = List<String>.generate(10, (i) => 'record-$i');
      final batch100 = List<String>.generate(_recordCount, (i) => 'record-$i');
      final query = BoxQuery(
        where: QueryComparison(
          field: 'group',
          operator: QueryOperator.equal,
          value: 3,
        ),
        limit: 10,
      );
      final queryPayload = BoxCodec.encode(<String, dynamic>{
        'where': <String, dynamic>{
          'type': 'comparison',
          'field': 'group',
          'operator': 'equal',
          'value': 3,
          'upperValue': null,
        },
        'sortBy': const <dynamic>[],
        'limit': 10,
        'offset': 0,
      });

      _emit(<String, Object>{
        'kind': 'context',
        'layer': 'dart_boundary_matrix',
        'os': Platform.operatingSystem,
        'dart_version': Platform.version,
        'processors': Platform.numberOfProcessors,
        'iterations': iterations,
        'samples': samples,
        'records': _recordCount,
      });

      Object? sink;

      await _measureAsync(
        layer: 'generated_frb',
        operation: 'get_all_10',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.getAll(boxName: box.name, keys: batch10);
        },
      );
      expect(sink, isA<List<frb.NativeBatchRecord>>());

      await _measureAsync(
        layer: 'native_adapter',
        operation: 'get_all_10',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await (api as NativeBatchReadApi).getAll(box.name, batch10);
        },
      );
      expect(sink, isA<List<NativeBatchRecord>>());

      await _measureAsync(
        layer: 'public_dart',
        operation: 'get_all_10',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box.getAll(batch10);
        },
      );
      expect(sink, isA<List<MapEntry<String, dynamic>>>());

      await _measureAsync(
        layer: 'generated_frb',
        operation: 'get_all_100',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.getAll(boxName: box.name, keys: batch100);
        },
      );

      await _measureAsync(
        layer: 'native_adapter',
        operation: 'get_all_100',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await (api as NativeBatchReadApi).getAll(box.name, batch100);
        },
      );

      final batch100Records =
          await (api as NativeBatchReadApi).getAll(box.name, batch100);
      final batch100Decoded = List<dynamic>.generate(
        batch100Records.length,
        (index) => BoxCodec.decode(batch100Records[index].value),
        growable: false,
      );

      _measureSync(
        layer: 'public_dart_component',
        operation: 'get_all_100_decode_only',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = List<dynamic>.generate(
            batch100Records.length,
            (index) => BoxCodec.decode(batch100Records[index].value),
            growable: false,
          );
        },
      );

      _measureSync(
        layer: 'public_dart_component',
        operation: 'get_all_100_materialize_predecoded',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = List<MapEntry<String, dynamic>>.generate(
            batch100Records.length,
            (index) => MapEntry<String, dynamic>(
              batch100Records[index].key,
              batch100Decoded[index],
            ),
            growable: false,
          );
        },
      );

      await _measureAsync(
        layer: 'public_dart',
        operation: 'get_all_100',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box.getAll(batch100);
        },
      );

      await _measureAsync(
        layer: 'generated_frb',
        operation: 'query_equal_limit_10',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.scanQuery(
            boxName: box.name,
            queryPayload: queryPayload,
          );
        },
      );
      expect(sink, isA<List<frb.NativeQueryRecord>>());

      await _measureAsync(
        layer: 'native_adapter',
        operation: 'query_equal_limit_10',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await (api as NativeQueryApi).scanQuery(
            box.name,
            queryPayload,
          );
        },
      );
      expect(sink, isA<List<NativeQueryRecord>>());

      final queryRecords = await (api as NativeQueryApi).scanQuery(
        box.name,
        queryPayload,
      );
      final queryDecoded = List<dynamic>.generate(
        queryRecords.length,
        (index) => BoxCodec.decode(queryRecords[index].value),
        growable: false,
      );

      _measureSync(
        layer: 'public_dart_component',
        operation: 'query_equal_limit_10_decode_only',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = List<dynamic>.generate(
            queryRecords.length,
            (index) => BoxCodec.decode(queryRecords[index].value),
            growable: false,
          );
        },
      );

      _measureSync(
        layer: 'public_dart_component',
        operation: 'query_equal_limit_10_materialize_predecoded',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = List<MapEntry<String, dynamic>>.generate(
            queryRecords.length,
            (index) => MapEntry<String, dynamic>(
              queryRecords[index].key,
              queryDecoded[index],
            ),
            growable: false,
          );
        },
      );

      await _measureAsync(
        layer: 'public_dart',
        operation: 'query_equal_limit_10',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await box.query(query);
        },
      );
      expect(sink, isA<List<MapEntry<String, dynamic>>>());

      await box.close();
      await DxtrBox.deleteBox('read_boundary_matrix');
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_READ_BOUNDARY_MATRIX_BENCHMARK=1 to run.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _measureAsync({
  required String layer,
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
    layer: layer,
    operation: operation,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

void _measureSync({
  required String layer,
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
    layer: layer,
    operation: operation,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

void _emitMeasurement({
  required String layer,
  required String operation,
  required int iterations,
  required int samples,
  required List<int> sampleNs,
}) {
  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': layer,
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
  print('DXTR_BOX_READ_BOUNDARY_MATRIX $line');
  final outputPath =
      Platform.environment['DXTR_BOX_READ_BOUNDARY_MATRIX_OUTPUT'];
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
