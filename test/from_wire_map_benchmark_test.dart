import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

const _iterations = 250;
const _samples = 5;
const _warmup = 25;
const _records = 100;

void main() {
  final enabled =
      Platform.environment['DXTR_BOX_FROM_WIRE_MAP_BENCHMARK'] == '1';

  test(
    'from-wire map conversion strategies execute',
    () {
      final decoded = List<dynamic>.generate(
        _records,
        (index) => msgpack.deserialize(
          BoxCodec.encode(<String, dynamic>{
            'id': index,
            'group': index % 10,
            'name': 'record-$index',
            'active': index.isEven,
          }),
        ),
        growable: false,
      );

      Object? sink;
      _measure(
        operation: 'map_comprehension_recursive',
        action: () {
          for (final value in decoded) {
            sink = _fromWireComprehension(value);
          }
        },
      );
      _measure(
        operation: 'map_loop_recursive',
        action: () {
          for (final value in decoded) {
            sink = _fromWireLoop(value);
          }
        },
      );
      expect(sink, isNotNull);
    },
    skip: enabled ? false : 'Set DXTR_BOX_FROM_WIRE_MAP_BENCHMARK=1 to run.',
  );
}

dynamic _fromWireComprehension(dynamic value) {
  if (value is! List || value.length != 2 || value.first is! String) {
    return value;
  }
  final tag = value[0] as String;
  final payload = value[1];
  if (tag != '@dxtr:map') return value;
  return <String, dynamic>{
    for (final pair in payload as List)
      (pair as List)[0] as String: _fromWireComprehension(pair[1]),
  };
}

dynamic _fromWireLoop(dynamic value) {
  if (value is! List || value.length != 2 || value.first is! String) {
    return value;
  }
  final tag = value[0] as String;
  final payload = value[1];
  if (tag != '@dxtr:map') return value;
  final result = <String, dynamic>{};
  for (final pairValue in payload as List) {
    final pair = pairValue as List;
    result[pair[0] as String] = _fromWireLoop(pair[1]);
  }
  return result;
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
    'layer': 'from_wire_map',
    'operation': operation,
    'iterations': _iterations,
    'samples': _samples,
    'median_ns_per_op': _median(sampleNs) / _iterations,
  });
}

void _emit(Map<String, Object> result) {
  final line = jsonEncode(result);
  // ignore: avoid_print
  print('DXTR_BOX_FROM_WIRE_MAP $line');
  final outputPath = Platform.environment['DXTR_BOX_FROM_WIRE_MAP_OUTPUT'];
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
