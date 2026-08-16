import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/codec.dart';
import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 1000;
const _defaultSamples = 7;
const _warmupIterations = 50;
const _encryptionKey = 'dxtr-box-read-path-benchmark';

void main() {
  final enabled = Platform.environment['DXTR_BOX_READ_PATH_BENCHMARK'] == '1';
  final iterations = _envInt(
    'DXTR_BOX_READ_PATH_DART_ITERATIONS',
    _defaultIterations,
  );
  final samples = _envInt(
    'DXTR_BOX_READ_PATH_DART_SAMPLES',
    _defaultSamples,
  );

  test(
    '0.5 read-path Dart and FRB diagnostic matrix executes',
    () async {
      expect(iterations, greaterThan(0));
      expect(samples, greaterThan(0));

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_read_path_benchmark_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      const api = FrbNativeDxtrApi();
      DxtrBox.bindNativeApi(api);
      await DxtrBox.init(path: root.path);

      final plain = await DxtrBox.open('read_path_plain');
      final encrypted = await DxtrBox.open(
        'read_path_encrypted',
        encryptionKey: _encryptionKey,
      );

      final payloads = <String, Map<String, dynamic>>{
        'small': <String, dynamic>{
          'id': 777,
          'name': 'record-777',
          'active': true,
          'tags': <String>['dxtr', 'read-path', 'benchmark'],
        },
        'medium': <String, dynamic>{
          'id': 778,
          'name': 'record-778',
          'active': false,
          'body': List<String>.filled(4096, 'x').join(),
          'tags': <String>['dxtr', 'read-path', 'benchmark'],
        },
      };

      for (final entry in payloads.entries) {
        await plain.put('${entry.key}-hit', entry.value);
        await encrypted.put('${entry.key}-hit', entry.value);
      }

      _emit(<String, Object>{
        'kind': 'context',
        'layer': 'dart',
        'os': Platform.operatingSystem,
        'dart_version': Platform.version,
        'processors': Platform.numberOfProcessors,
        'iterations': iterations,
        'samples': samples,
      });

      Object? sink;
      for (final entry in payloads.entries) {
        final sizeName = entry.key;
        final key = '$sizeName-hit';
        final missKey = '$sizeName-missing';
        final encoded = DxtrCodec.encode(entry.value);

        _measureSync(
          operation: 'dart_dxtr_codec_decode',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () {
            sink = DxtrCodec.decode(encoded);
          },
        );
        expect(sink, isA<Map<dynamic, dynamic>>());

        await _measureAsync(
          operation: 'native_adapter_get',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await api.get(plain.name, key);
          },
        );
        expect(sink, isA<Uint8List>());

        await _measureAsync(
          operation: 'native_adapter_get',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'miss',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await api.get(plain.name, missKey);
          },
        );
        expect(sink, isNull);

        await _measureAsync(
          operation: 'public_box_get',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await plain.get(key);
          },
        );
        expect(sink, isA<Map<dynamic, dynamic>>());

        await _measureAsync(
          operation: 'public_box_get',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'miss',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await plain.get(missKey);
          },
        );
        expect(sink, isNull);

        await _measureAsync(
          operation: 'native_adapter_get',
          payload: sizeName,
          mode: 'encrypted',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await api.get(encrypted.name, key);
          },
        );
        expect(sink, isA<Uint8List>());

        await _measureAsync(
          operation: 'native_adapter_get',
          payload: sizeName,
          mode: 'encrypted',
          outcome: 'miss',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await api.get(encrypted.name, missKey);
          },
        );
        expect(sink, isNull);

        await _measureAsync(
          operation: 'public_box_get',
          payload: sizeName,
          mode: 'encrypted',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await encrypted.get(key);
          },
        );
        expect(sink, isA<Map<dynamic, dynamic>>());

        await _measureAsync(
          operation: 'public_box_get',
          payload: sizeName,
          mode: 'encrypted',
          outcome: 'miss',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await encrypted.get(missKey);
          },
        );
        expect(sink, isNull);

        await _measureAsync(
          operation: 'native_adapter_contains_key',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await api.containsKey(plain.name, key);
          },
        );
        expect(sink, isTrue);

        await _measureAsync(
          operation: 'native_adapter_contains_key',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'miss',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await api.containsKey(plain.name, missKey);
          },
        );
        expect(sink, isFalse);

        await _measureAsync(
          operation: 'public_box_contains_key',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'hit',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await plain.containsKey(key);
          },
        );
        expect(sink, isTrue);

        await _measureAsync(
          operation: 'public_box_contains_key',
          payload: sizeName,
          mode: 'plaintext',
          outcome: 'miss',
          iterations: iterations,
          samples: samples,
          action: () async {
            sink = await plain.containsKey(missKey);
          },
        );
        expect(sink, isFalse);
      }

      await plain.close();
      await encrypted.close();
      await DxtrBox.deleteBox('read_path_plain');
      await DxtrBox.deleteBox('read_path_encrypted');
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_READ_PATH_BENCHMARK=1 to run 0.5 read-path diagnostics.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

void _measureSync({
  required String operation,
  required String payload,
  required String mode,
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
    payload: payload,
    mode: mode,
    outcome: outcome,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

Future<void> _measureAsync({
  required String operation,
  required String payload,
  required String mode,
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
    payload: payload,
    mode: mode,
    outcome: outcome,
    iterations: iterations,
    samples: samples,
    sampleNs: sampleNs,
  );
}

void _emitMeasurement({
  required String operation,
  required String payload,
  required String mode,
  required String outcome,
  required int iterations,
  required int samples,
  required List<int> sampleNs,
}) {
  sampleNs.sort();
  final medianTotalNs = _median(sampleNs);
  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': 'dart',
    'operation': operation,
    'payload': payload,
    'mode': mode,
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
  print('DXTR_BOX_READ_PATH_DART $line');
  final outputPath = Platform.environment['DXTR_BOX_READ_PATH_DART_OUTPUT'];
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
