import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

const _iterations = 500;
const _samples = 5;
const _warmup = 50;
const _enabledEnv = 'DXTR_BOX_CODEC_ENCODE_COPY_BENCHMARK';
const _outputEnv = 'DXTR_BOX_CODEC_ENCODE_COPY_OUTPUT';
const _skipReason = 'Set DXTR_BOX_CODEC_ENCODE_COPY_BENCHMARK=1 to run.';

void main() {
  final enabled = Platform.environment[_enabledEnv] == '1';

  test(
    'codec encode copy diagnostic executes',
    () {
      final value = <String, dynamic>{
        'id': 7,
        'group': 3,
        'name': 'codec-encode-copy',
        'active': true,
        'items': List<int>.generate(32, (index) => index, growable: false),
      };
      final wire = <dynamic>[
        '@dxtr:map',
        <dynamic>[
          <dynamic>['id', 7],
          <dynamic>['group', 3],
          <dynamic>['name', 'codec-encode-copy'],
          <dynamic>['active', true],
          <dynamic>[
            'items',
            <dynamic>[
              '@dxtr:list',
              List<int>.generate(32, (index) => index, growable: false),
            ],
          ],
        ],
      ];

      Object? sink;
      _measure(
        operation: 'msgpack_serialize_direct',
        action: () {
          sink = msgpack.serialize(wire);
        },
      );
      _measure(
        operation: 'msgpack_serialize_then_copy',
        action: () {
          sink = Uint8List.fromList(msgpack.serialize(wire));
        },
      );
      _measure(
        operation: 'box_codec_encode',
        action: () {
          sink = BoxCodec.encode(value);
        },
      );
      expect(sink, isNotNull);
    },
    skip: enabled ? false : _skipReason,
  );
}

void _measure({required String operation, required void Function() action}) {
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
  _emit(<String, Object>{
    'kind': 'measurement',
    'layer': 'codec_encode_copy',
    'operation': operation,
    'iterations': _iterations,
    'samples': _samples,
    'median_ns_per_op': _median(sampleNs) / _iterations,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_CODEC_ENCODE_COPY $line');
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
