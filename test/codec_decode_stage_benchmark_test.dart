import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

const _defaultIterations = 250;
const _defaultSamples = 5;
const _warmupIterations = 25;
const _getAllCount = 100;
const _queryCount = 10;
const _enabledEnv = 'DXTR_BOX_CODEC_DECODE_STAGE_BENCHMARK';
const _iterationsEnv = 'DXTR_BOX_CODEC_DECODE_STAGE_ITERATIONS';
const _samplesEnv = 'DXTR_BOX_CODEC_DECODE_STAGE_SAMPLES';
const _outputEnv = 'DXTR_BOX_CODEC_DECODE_STAGE_OUTPUT';
const _skipMessage = 'Set DXTR_BOX_CODEC_DECODE_STAGE_BENCHMARK=1 to run.';

void main() {
  final enabled = Platform.environment[_enabledEnv] == '1';
  final iterations = _envInt(_iterationsEnv, _defaultIterations);
  final samples = _envInt(_samplesEnv, _defaultSamples);
  final skip = enabled ? false : _skipMessage;

  test(
    'codec decode stage decomposition executes',
    () {
      final getAllPayloads = List<Uint8List>.generate(
        _getAllCount,
        _payloadForIndex,
        growable: false,
      );
      final queryPayloads = List<Uint8List>.generate(
        _queryCount,
        (index) => _payloadForIndex(index * 10 + 3),
        growable: false,
      );

      _emit(<String, Object>{
        'kind': 'context',
        'layer': 'codec_decode_stage',
        'os': Platform.operatingSystem,
        'dart_version': Platform.version,
        'processors': Platform.numberOfProcessors,
        'iterations': iterations,
        'samples': samples,
        'get_all_records': _getAllCount,
        'query_records': _queryCount,
      });

      Object? sink;

      _measureSync(
        operation: 'get_all_100_deserialize_only',
        iterations: iterations,
        samples: samples,
        action: () {
          for (final payload in getAllPayloads) {
            sink = msgpack.deserialize(_normalizedInput(payload));
          }
        },
      );

      _measureSync(
        operation: 'get_all_100_box_codec_decode',
        iterations: iterations,
        samples: samples,
        action: () {
          for (final payload in getAllPayloads) {
            sink = BoxCodec.decode(payload);
          }
        },
      );

      _measureSync(
        operation: 'query_10_deserialize_only',
        iterations: iterations,
        samples: samples,
        action: () {
          for (final payload in queryPayloads) {
            sink = msgpack.deserialize(_normalizedInput(payload));
          }
        },
      );

      _measureSync(
        operation: 'query_10_box_codec_decode',
        iterations: iterations,
        samples: samples,
        action: () {
          for (final payload in queryPayloads) {
            sink = BoxCodec.decode(payload);
          }
        },
      );

      expect(sink, isNotNull);
    },
    skip: skip,
  );
}

Uint8List _payloadForIndex(int index) {
  return BoxCodec.encode(<String, dynamic>{
    'id': index,
    'group': index % 10,
    'name': 'record-$index',
    'active': index.isEven,
  });
}

Uint8List _normalizedInput(Uint8List bytes) {
  final startsAtZero = bytes.offsetInBytes == 0;
  final spansBuffer = bytes.lengthInBytes == bytes.buffer.lengthInBytes;
  if (startsAtZero && spansBuffer) {
    return bytes;
  }
  return Uint8List.fromList(bytes);
}

void _measureSync({
  required String operation,
  required int iterations,
  required int samples,
  required void Function() action,
}) {
  for (var index = 0; index < _warmupIterations; index++) {
    action();
  }

  final sampleNs = <int>[];
  for (var sample = 0; sample < samples; sample++) {
    final watch = Stopwatch()..start();
    for (var index = 0; index < iterations; index++) {
      action();
    }
    watch.stop();
    sampleNs.add(watch.elapsedMicroseconds * 1000);
  }
  sampleNs.sort();

  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': 'codec_decode_stage',
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
  print('DXTR_BOX_CODEC_DECODE_STAGE $line');
  final outputPath = Platform.environment[_outputEnv];
  if (outputPath == null || outputPath.isEmpty) return;
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

int _envInt(String name, int fallback) {
  return int.tryParse(Platform.environment[name] ?? '') ?? fallback;
}

num _median(List<int> ordered) {
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}
