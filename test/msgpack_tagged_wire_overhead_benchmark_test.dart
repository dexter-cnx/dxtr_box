import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

const _iterations = 1000;
const _samples = 7;
const _warmup = 100;
const _enabledEnv = 'DXTR_BOX_MSGPACK_TAGGED_WIRE_BENCHMARK';
const _outputEnv = 'DXTR_BOX_MSGPACK_TAGGED_WIRE_OUTPUT';
const _skipReason = 'Set DXTR_BOX_MSGPACK_TAGGED_WIRE_BENCHMARK=1 to run.';
const _sizes = <int>[4, 16, 64];

void main() {
  final enabled = Platform.environment[_enabledEnv] == '1';

  test(
    'msgpack tagged wire overhead diagnostic executes',
    () {
      Object? sink;
      for (final size in _sizes) {
        final nativeMap = <String, dynamic>{
          for (var index = 0; index < size; index++) 'field-$index': index,
        };
        final taggedMap = <dynamic>[
          '@dxtr:map',
          <dynamic>[
            for (var index = 0; index < size; index++)
              <dynamic>['field-$index', index],
          ],
        ];
        final nativeList = List<int>.generate(
          size,
          (index) => index,
          growable: false,
        );
        final taggedList = <dynamic>['@dxtr:list', nativeList];

        final cases = <String, dynamic>{
          'native_map': nativeMap,
          'tagged_map': taggedMap,
          'native_list': nativeList,
          'tagged_list': taggedList,
        };
        for (final entry in cases.entries) {
          final payload = msgpack.serialize(entry.value);
          _measure(
            operation: entry.key,
            logicalItems: size,
            payloadBytes: payload.lengthInBytes,
            action: () {
              sink = msgpack.deserialize(payload);
            },
          );
        }
      }
      expect(sink, isNotNull);
    },
    skip: enabled ? false : _skipReason,
  );
}

void _measure({
  required String operation,
  required int logicalItems,
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
    'layer': 'msgpack_tagged_wire',
    'operation': operation,
    'logical_items': logicalItems,
    'iterations': _iterations,
    'samples': _samples,
    'payload_bytes': payloadBytes,
    'median_ns_per_op': medianNs,
    'median_ns_per_item': medianNs / logicalItems,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_MSGPACK_TAGGED_WIRE $line');
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
