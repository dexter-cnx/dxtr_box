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
    'candidate decoder matches the pinned dxtr_box/1 wire corpus',
    () {
      for (final fixture in _compatibilityPayloads) {
        final current = msgpack.deserialize(fixture.bytes);
        final candidate = pro_mpack.deserialize(fixture.bytes);
        expect(
          _comparable(candidate),
          _comparable(current),
          reason: fixture.name,
        );
      }
    },
    skip: enabled ? false : 'Set $_enabledEnv=1 to run.',
  );

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

final _compatibilityPayloads = <_WireFixture>[
  for (final entry in <String, String>{
    'null': 'c0',
    'bool_true': 'c3',
    'int_positive': '2a',
    'int_negative': 'f9',
    'double': 'cb400c000000000000',
    'string': 'a464787472',
    'bytes': '92ab40647874723a6279746573c4040001feff',
    'datetime': '92ae40647874723a6461746574696d65cf00060dedc04fb580',
    'list': '92aa40647874723a6c6973749301a374776fc3',
    'map': '92a940647874723a6d61709292a269640792a46e616d65a3626f78',
    'nested':
        '92a940647874723a6d61709192a56974656d7392aa40647874723a6c697374920192a940647874723a6d61709192a26f6bc3',
  }.entries)
    _WireFixture(entry.key, _bytes(entry.value)),
  for (final entry in <int, List<int>>{
    127: <int>[0x7f],
    128: <int>[0xcc, 0x80],
    255: <int>[0xcc, 0xff],
    256: <int>[0xcd, 0x01, 0x00],
    65535: <int>[0xcd, 0xff, 0xff],
    65536: <int>[0xce, 0x00, 0x01, 0x00, 0x00],
    4294967295: <int>[0xce, 0xff, 0xff, 0xff, 0xff],
    4294967296: <int>[0xcf, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00],
    -32: <int>[0xe0],
    -33: <int>[0xd0, 0xdf],
    -128: <int>[0xd0, 0x80],
    -129: <int>[0xd1, 0xff, 0x7f],
    -32768: <int>[0xd1, 0x80, 0x00],
    -32769: <int>[0xd2, 0xff, 0xff, 0x7f, 0xff],
    -2147483648: <int>[0xd2, 0x80, 0x00, 0x00, 0x00],
    -2147483649: <int>[0xd3, 0xff, 0xff, 0xff, 0xff, 0x7f, 0xff, 0xff, 0xff],
  }.entries)
    _WireFixture('int_${entry.key}', Uint8List.fromList(entry.value)),
  for (final length in <int>[31, 32, 255, 256, 65535, 65536])
    _WireFixture(
      'string_length_$length',
      Uint8List.fromList(_messagePackStringBytes(length, 0x73)),
    ),
  for (final length in <int>[255, 256, 65535, 65536])
    _WireFixture(
      'bytes_length_$length',
      Uint8List.fromList(<int>[
        0x92,
        ..._fixStringBytes('@dxtr:bytes'),
        ..._messagePackBinaryBytes(length),
      ]),
    ),
  for (final length in <int>[15, 16, 65535, 65536])
    _WireFixture(
      'list_length_$length',
      Uint8List.fromList(<int>[
        0x92,
        ..._fixStringBytes('@dxtr:list'),
        ..._messagePackArrayPrefix(length),
        ...List<int>.filled(length, 0, growable: false),
      ]),
    ),
];

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

final class _WireFixture {
  const _WireFixture(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

Uint8List _bytes(String hex) {
  return Uint8List.fromList(<int>[
    for (var offset = 0; offset < hex.length; offset += 2)
      int.parse(hex.substring(offset, offset + 2), radix: 16),
  ]);
}

List<int> _fixStringBytes(String value) {
  final bytes = utf8.encode(value);
  return <int>[0xa0 | bytes.length, ...bytes];
}

List<int> _messagePackStringBytes(int length, int byte) {
  final prefix = switch (length) {
    <= 31 => <int>[0xa0 | length],
    <= 255 => <int>[0xd9, length],
    <= 65535 => <int>[0xda, length >> 8, length & 0xff],
    _ => <int>[
        0xdb,
        (length >> 24) & 0xff,
        (length >> 16) & 0xff,
        (length >> 8) & 0xff,
        length & 0xff,
      ],
  };
  return <int>[...prefix, ...List<int>.filled(length, byte, growable: false)];
}

List<int> _messagePackBinaryBytes(int length) {
  final prefix = switch (length) {
    <= 255 => <int>[0xc4, length],
    <= 65535 => <int>[0xc5, length >> 8, length & 0xff],
    _ => <int>[
        0xc6,
        (length >> 24) & 0xff,
        (length >> 16) & 0xff,
        (length >> 8) & 0xff,
        length & 0xff,
      ],
  };
  return <int>[...prefix, ...List<int>.filled(length, 0, growable: false)];
}

List<int> _messagePackArrayPrefix(int length) {
  return switch (length) {
    <= 15 => <int>[0x90 | length],
    <= 65535 => <int>[0xdc, length >> 8, length & 0xff],
    _ => <int>[
        0xdd,
        (length >> 24) & 0xff,
        (length >> 16) & 0xff,
        (length >> 8) & 0xff,
        length & 0xff,
      ],
  };
}

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
