import 'dart:typed_data';

import 'package:dxtr_box/src/codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips supported dynamic values', () {
    final values = <dynamic>[
      null,
      true,
      42,
      3.14,
      'Dxtr',
      <dynamic>[1, 'two', false],
      <String, dynamic>{
        'nested': <dynamic>[1, 2],
      },
      Uint8List.fromList(<int>[1, 2, 3]),
      DateTime.utc(2026, 8, 15, 1, 2, 3),
    ];

    for (final value in values) {
      final decoded = DxtrCodec.decode(DxtrCodec.encode(value));
      if (value is Uint8List) {
        expect(decoded, orderedEquals(value));
      } else {
        expect(decoded, value);
      }
    }
  });

  test('rejects non-string map keys', () {
    expect(
      () => DxtrCodec.encode(<dynamic, dynamic>{1: 'bad'}),
      throwsArgumentError,
    );
  });
}
