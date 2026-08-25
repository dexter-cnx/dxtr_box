import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

const _iterations = 1000;
const _samples = 7;
const _warmup = 100;
const _enabledEnv = 'DXTR_BOX_MSGPACK_DESERIALIZE_SHAPE_BENCHMARK';
const _outputEnv = 'DXTR_BOX_MSGPACK_DESERIALIZE_SHAPE_OUTPUT';
const _skipReason =
    'Set DXTR_BOX_MSGPACK_DESERIALIZE_SHAPE_BENCHMARK=1 to run.';

void main() {
  final enabled = Platform.environment[_enabledEnv] == '1';

  test(
    'msgpack deserialize shape diagnostic executes',
    () {
      final cases = <String, dynamic>{
        'flat_map': <String, dynamic>{
          'id': 42,
          'group': 7,
          'name': 'record-42',
          'active': true,
        },
        'nested_map': <String, dynamic>{
          'id': 42,
          'profile': <String, dynamic>{
            'name': 'record-42',
            'flags': <String, dynamic>{'active': true, 'group': 7},
          },
        },
        'list_heavy': <String, dynamic>{
          'id': 42,
          'items': List<int>.generate(64, (index) => index, growable: false),
        },
        'string_heavy': <String, dynamic>{
          'id': 42,
          'text': List<String>.filled(8, 'dxtr-box-messagepack').join('-'),
        },
        'bytes_heavy': <String, dynamic>{
          'id': 42,
          'bytes': Uint8List.fromList(
            List<int>.generate(256, (index) => index & 0xff, growable: false),
          ),
        },
      };

      Object? sink;
      for (final entry in cases.entries) {
        final payload = BoxCodec.encode(entry.value);
        _measure(
          operation: entry.key,
          payloadBytes: payload.lengthInBytes,
          action: () {
            sink = msgpack.deserialize(payload);
          },
        );
      }
      expect(sink, isNotNull);
    },
    skip: enabled ? false : _skipReason,
  );
}

void _measure({
  required String operation,
  required int payloadBytes,
  required void Function() action,
}) {
  for (var index = 0; index < _warmup; index++) {
    action();
  }

  final sampleNs = <int>[];
  for (var sample = 0; sample < _samples; sample++) {
    final watch = Stopwatch()..start();
    for (var index = 0; index < _iterations; index++) {
      action();
    }
    watch.stop();
    sampleNs.add(watch.elapsedMicroseconds * 1000);
  }
  sampleNs.sort();
  final medianNs = _median(sampleNs) / _iterations;

  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': 'msgpack_deserialize_shape',
    'operation': operation,
    'iterations': _iterations,
    'samples': _samples,
    'payload_bytes': payloadBytes,
    'median_ns_per_op': medianNs,
    'median_ns_per_byte': medianNs / payloadBytes,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_MSGPACK_DESERIALIZE_SHAPE $line');
  final outputPath = Platform.environment[_outputEnv];
  if (outputPath == null || outputPath.isEmpty) return;
  final file = File(outputPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

num _median(List<int> ordered) {
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}
