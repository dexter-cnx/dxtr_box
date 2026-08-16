import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/codec.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:dxtr_box/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 1000;
const _defaultSamples = 7;
const _warmupIterations = 50;

void main() {
  final enabled =
      Platform.environment['DXTR_BOX_READ_PATH_BOUNDARY_BENCHMARK'] == '1';
  final iterations = _envInt(
    'DXTR_BOX_READ_PATH_DART_ITERATIONS',
    _defaultIterations,
  );
  final samples = _envInt(
    'DXTR_BOX_READ_PATH_DART_SAMPLES',
    _defaultSamples,
  );

  test(
    '0.5 PR2 generated-FRB boundary diagnostic executes',
    () async {
      expect(iterations, greaterThan(0));
      expect(samples, greaterThan(0));

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_read_path_boundary_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      const api = FrbNativeDxtrApi();
      DxtrBox.bindNativeApi(api);
      await DxtrBox.init(path: root.path);
      final box = await DxtrBox.open('read_path_boundary');

      const key = 'boundary-hit';
      const missKey = 'boundary-missing';
      final encoded = DxtrCodec.encode(<String, Object>{
        'id': 779,
        'name': 'boundary-record',
        'active': true,
      });
      await api.put(box.name, key, encoded);

      _emit(<String, Object>{
        'kind': 'context',
        'layer': 'dart_boundary',
        'os': Platform.operatingSystem,
        'dart_version': Platform.version,
        'processors': Platform.numberOfProcessors,
        'iterations': iterations,
        'samples': samples,
        'purpose':
            'Compare generated FRB calls with the Dart native adapter and a sync FRB control without adding benchmark-only native API surface.',
      });

      Object? sink;

      _measureSync(
        operation: 'dart_sync_noop',
        outcome: 'control',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = true;
        },
      );
      expect(sink, isTrue);

      await _measureAsync(
        operation: 'dart_future_value',
        outcome: 'control',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await Future<bool>.value(true);
        },
      );
      expect(sink, isTrue);

      _measureSync(
        operation: 'generated_frb_box_exists_sync',
        outcome: 'hit',
        iterations: iterations,
        samples: samples,
        action: () {
          sink = frb.boxExists(name: box.name);
        },
      );
      expect(sink, isTrue);

      await _measureAsync(
        operation: 'native_adapter_box_exists_sync_wrapped_async',
        outcome: 'hit',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await api.boxExists(box.name);
        },
      );
      expect(sink, isTrue);

      await _measureAsync(
        operation: 'generated_frb_get_async',
        outcome: 'hit',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.get_(boxName: box.name, key: key);
        },
      );
      expect(sink, isA<Uint8List>());

      await _measureAsync(
        operation: 'native_adapter_get_async',
        outcome: 'hit',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await api.get(box.name, key);
        },
      );
      expect(sink, isA<Uint8List>());

      await _measureAsync(
        operation: 'generated_frb_get_async',
        outcome: 'miss',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.get_(boxName: box.name, key: missKey);
        },
      );
      expect(sink, isNull);

      await _measureAsync(
        operation: 'generated_frb_contains_key_async',
        outcome: 'hit',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.containsKey(boxName: box.name, key: key);
        },
      );
      expect(sink, isTrue);

      await _measureAsync(
        operation: 'native_adapter_contains_key_async',
        outcome: 'hit',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await api.containsKey(box.name, key);
        },
      );
      expect(sink, isTrue);

      await _measureAsync(
        operation: 'generated_frb_contains_key_async',
        outcome: 'miss',
        iterations: iterations,
        samples: samples,
        action: () async {
          sink = await frb.containsKey(boxName: box.name, key: missKey);
        },
      );
      expect(sink, isFalse);

      await box.close();
      await DxtrBox.deleteBox('read_path_boundary');
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_READ_PATH_BOUNDARY_BENCHMARK=1 to run PR2 boundary diagnostics.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

void _measureSync({
  required String operation,
  required String outcome,
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
  _emitMeasurement(
    operation: operation,
    outcome: outcome,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

Future<void> _measureAsync({
  required String operation,
  required String outcome,
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
  _emitMeasurement(
    operation: operation,
    outcome: outcome,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

void _emitMeasurement({
  required String operation,
  required String outcome,
  required int iterations,
  required int samples,
  required List<int> sampleNs,
}) {
  sampleNs.sort();
  final medianTotalNs = _median(sampleNs);
  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': 'dart_boundary',
    'operation': operation,
    'outcome': outcome,
    'iterations': iterations,
    'samples': samples,
    'sample_ns': sampleNs,
    'median_ns_per_op': medianTotalNs / iterations,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_READ_PATH_BOUNDARY $line');
  final outputPath = Platform.environment['DXTR_BOX_READ_PATH_BOUNDARY_OUTPUT'];
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
