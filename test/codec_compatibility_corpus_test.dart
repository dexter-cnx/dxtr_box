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

final class _Fixture {
  const _Fixture(this.name, this.value, this.hex);

  final String name;
  final dynamic value;
  final String hex;
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

dynamic _comparable(dynamic value) {
  if (value is Uint8List) {
    return <dynamic>['bytes', ...value];
  }
  if (value is DateTime) {
    return <dynamic>['datetime', value.toUtc().microsecondsSinceEpoch];
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
