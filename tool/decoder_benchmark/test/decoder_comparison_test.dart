import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import 'package:pro_mpack/pro_mpack.dart' as pro_mpack;

const _iterations = 1000;
const _samples = 7;
const _warmup = 100;
const _enabledEnv = 'DXTR_BOX_DECODER_COMPARISON_BENCHMARK';
const _outputEnv = 'DXTR_BOX_DECODER_COMPARISON_OUTPUT';

void main() {
  final enabled = Platform.environment[_enabledEnv] == '1';

  test(
    'decoder comparison uses identical dxtr_box/1 payload bytes',
    () {
      Object? sink;
      for (final entry in _cases.entries) {
        final payload = BoxCodec.encode(entry.value);
        final current = msgpack.deserialize(payload);
        final candidate = pro_mpack.deserialize(payload);
        expect(_comparable(candidate), _comparable(current));

        _measure(
          decoder: 'msgpack_dart',
          operation: entry.key,
          payloadBytes: payload.lengthInBytes,
          action: () {
            sink = msgpack.deserialize(payload);
          },
        );
        _measure(
          decoder: 'pro_mpack',
          operation: entry.key,
          payloadBytes: payload.lengthInBytes,
          action: () {
            sink = pro_mpack.deserialize(payload);
          },
        );
      }
      expect(sink, isNotNull);
    },
    skip: enabled ? false : 'Set $_enabledEnv=1 to run.',
  );
}

final _cases = <String, dynamic>{
  'flat_map_16': <String, dynamic>{
    for (var index = 0; index < 16; index++) 'field-$index': index,
  },
  'flat_map_64': <String, dynamic>{
    for (var index = 0; index < 64; index++) 'field-$index': index,
  },
  'list_256': List<int>.generate(256, (index) => index, growable: false),
  'bytes_4096': Uint8List.fromList(
    List<int>.generate(4096, (index) => index & 0xff, growable: false),
  ),
  'nested': <String, dynamic>{
    'items': <dynamic>[
      for (var index = 0; index < 32; index++)
        <String, dynamic>{
          'id': index,
          'name': 'item-$index',
          'flags': <dynamic>[true, false, index.isEven],
        },
    ],
  },
};

void _measure({
  required String decoder,
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
    'layer': 'decoder_comparison',
    'decoder': decoder,
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
  print('DXTR_BOX_DECODER_COMPARISON $line');
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

dynamic _comparable(dynamic value) {
  if (value is Uint8List) return <dynamic>['bytes', ...value];
  if (value is List) {
    return value.map<dynamic>(_comparable).toList(growable: false);
  }
  if (value is Map) {
    return <dynamic>[
      for (final entry in value.entries)
        <dynamic>[_comparable(entry.key), _comparable(entry.value)],
    ];
  }
  return value;
}
