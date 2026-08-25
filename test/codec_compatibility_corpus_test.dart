import 'dart:convert';
import 'dart:typed_data';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('dxtr_box/1 codec byte compatibility corpus', () {
    for (final fixture in _fixtures) {
      test('${fixture.name} preserves exact bytes and value semantics', () {
        final encoded = BoxCodec.encode(fixture.value);
        expect(_hex(encoded), fixture.hex);

        final decoded = BoxCodec.decode(_bytes(fixture.hex));
        expect(_comparable(decoded), _comparable(fixture.value));
      });
    }

    for (final fixture in _boundaryFixtures) {
      test('${fixture.name} preserves MessagePack width boundary', () {
        final encoded = BoxCodec.encode(fixture.value);
        expect(encoded, orderedEquals(fixture.bytes));

        final decoded = BoxCodec.decode(Uint8List.fromList(fixture.bytes));
        expect(_comparable(decoded), _comparable(fixture.value));
      });
    }
  });
}

final _fixtures = <_Fixture>[
  const _Fixture('null', null, 'c0'),
  const _Fixture('bool_true', true, 'c3'),
  const _Fixture('int_positive', 42, '2a'),
  const _Fixture('int_negative', -7, 'f9'),
  const _Fixture('double', 3.5, 'cb400c000000000000'),
  const _Fixture('string', 'dxtr', 'a464787472'),
  _Fixture(
    'bytes',
    Uint8List.fromList(<int>[0, 1, 254, 255]),
    '92ab40647874723a6279746573c4040001feff',
  ),
  _Fixture(
    'datetime',
    DateTime.fromMicrosecondsSinceEpoch(1704164645123456, isUtc: true),
    '92ae40647874723a6461746574696d65cf00060dedc04fb580',
  ),
  const _Fixture(
    'list',
    <dynamic>[1, 'two', true],
    '92aa40647874723a6c6973749301a374776fc3',
  ),
  const _Fixture(
    'map',
    <String, dynamic>{'id': 7, 'name': 'box'},
    '92a940647874723a6d61709292a269640792a46e616d65a3626f78',
  ),
  const _Fixture(
    'nested',
    <String, dynamic>{
      'items': <dynamic>[
        1,
        <String, dynamic>{'ok': true},
      ],
    },
    '92a940647874723a6d61709192a56974656d7392aa40647874723a6c697374920192a940647874723a6d61709192a26f6bc3',
  ),
];

final _boundaryFixtures = <_BoundaryFixture>[
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
    -2147483649: <int>[
      0xd3,
      0xff,
      0xff,
      0xff,
      0xff,
      0x7f,
      0xff,
      0xff,
      0xff,
    ],
  }.entries)
    _BoundaryFixture('int_${entry.key}', entry.key, entry.value),
  for (final length in <int>[31, 32, 255, 256, 65535, 65536])
    _BoundaryFixture(
      'string_length_$length',
      _repeatAscii(length, 0x73),
      _messagePackStringBytes(length, 0x73),
    ),
  for (final length in <int>[255, 256, 65535, 65536])
    _BoundaryFixture(
      'bytes_length_$length',
      Uint8List(length),
      <int>[
        0x92,
        ..._fixStringBytes('@dxtr:bytes'),
        ..._messagePackBinaryBytes(length),
      ],
    ),
  for (final length in <int>[15, 16, 65535, 65536])
    _BoundaryFixture(
      'list_length_$length',
      List<int>.filled(length, 0, growable: false),
      <int>[
        0x92,
        ..._fixStringBytes('@dxtr:list'),
        ..._messagePackArrayPrefix(length),
        ...List<int>.filled(length, 0, growable: false),
      ],
    ),
];

final class _Fixture {
  const _Fixture(this.name, this.value, this.hex);

  final String name;
  final dynamic value;
  final String hex;
}

final class _BoundaryFixture {
  const _BoundaryFixture(this.name, this.value, this.bytes);

  final String name;
  final dynamic value;
  final List<int> bytes;
}

String _hex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List _bytes(String hex) {
  return Uint8List.fromList(<int>[
    for (var offset = 0; offset < hex.length; offset += 2)
      int.parse(hex.substring(offset, offset + 2), radix: 16),
  ]);
}

String _repeatAscii(int length, int byte) {
  return String.fromCharCodes(List<int>.filled(length, byte, growable: false));
}

List<int> _fixStringBytes(String value) {
  final bytes = utf8.encode(value);
  if (bytes.length > 31) {
    throw ArgumentError.value(value, 'value', 'Expected fixstr-sized value');
  }
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

dynamic _comparable(dynamic value) {
  if (value is Uint8List) {
    return <dynamic>['bytes', ...value];
  }
  if (value is DateTime) {
    return <dynamic>[
      'datetime',
      value.microsecondsSinceEpoch,
      value.isUtc,
    ];
  }
  if (value is List) {
    return value.map<dynamic>(_comparable).toList(growable: false);
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key as String: _comparable(entry.value),
    };
  }
  return value;
}
