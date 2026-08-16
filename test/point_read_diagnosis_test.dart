import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/codec.dart';
import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 500;
const _defaultSamples = 5;
const _datasetSize = 1000;
const _encryptionKey = 'dxtr-box-point-read-diagnosis';

void main() {
  final enabled = Platform.environment['DXTR_BOX_POINT_READ_DIAGNOSIS'] == '1';
  final iterations = int.tryParse(
        Platform.environment['DXTR_BOX_POINT_READ_ITERATIONS'] ?? '',
      ) ??
      _defaultIterations;
  final samples = int.tryParse(
        Platform.environment['DXTR_BOX_POINT_READ_SAMPLES'] ?? '',
      ) ??
      _defaultSamples;

  test(
    'point get and containsKey diagnostic matrix executes',
    () async {
      expect(iterations, greaterThan(0));
      expect(samples, greaterThan(0));

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_point_read_diagnosis_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      const api = FrbNativeDxtrApi();
      DxtrBox.bindNativeApi(api);
      await DxtrBox.init(path: root.path);

      final plain = await DxtrBox.open('point_read_plain');
      final encrypted = await DxtrBox.open(
        'point_read_encrypted',
        encryptionKey: _encryptionKey,
      );

      final entries = <String, dynamic>{
        for (var i = 0; i < _datasetSize; i++)
          'k${i.toString().padLeft(6, '0')}': <String, dynamic>{
            'id': i,
            'name': 'record-$i',
            'active': i.isEven,
            'tags': <String>['dxtr', 'point-read', 'diagnosis'],
          },
      };
      await plain.putAll(entries);
      await encrypted.putAll(entries);

      const existingKey = 'k000777';
      const missingKey = 'k999999';
      final encoded = await api.get(plain.name, existingKey);
      expect(encoded, isNotNull);
      final encodedValue = encoded!;

      final cases = <_DiagnosticCase>[
        _DiagnosticCase(
          name: 'public_get_plain_hit',
          action: () async {
            expect(await plain.get(existingKey), isA<Map<dynamic, dynamic>>());
          },
        ),
        _DiagnosticCase(
          name: 'native_get_plain_hit',
          action: () async {
            expect(await api.get(plain.name, existingKey), isNotNull);
          },
        ),
        _DiagnosticCase(
          name: 'decode_only_plain_hit',
          action: () async {
            expect(DxtrCodec.decode(encodedValue), isA<Map<dynamic, dynamic>>());
          },
        ),
        _DiagnosticCase(
          name: 'public_get_plain_miss',
          action: () async {
            expect(await plain.get(missingKey), isNull);
          },
        ),
        _DiagnosticCase(
          name: 'native_get_plain_miss',
          action: () async {
            expect(await api.get(plain.name, missingKey), isNull);
          },
        ),
        _DiagnosticCase(
          name: 'public_contains_hit',
          action: () async {
            expect(await plain.containsKey(existingKey), isTrue);
          },
        ),
        _DiagnosticCase(
          name: 'native_contains_hit',
          action: () async {
            expect(await api.containsKey(plain.name, existingKey), isTrue);
          },
        ),
        _DiagnosticCase(
          name: 'public_contains_miss',
          action: () async {
            expect(await plain.containsKey(missingKey), isFalse);
          },
        ),
        _DiagnosticCase(
          name: 'native_contains_miss',
          action: () async {
            expect(await api.containsKey(plain.name, missingKey), isFalse);
          },
        ),
        _DiagnosticCase(
          name: 'metadata_contains_hit',
          action: () async {
            expect(plain.keys.contains(existingKey), isTrue);
          },
        ),
        _DiagnosticCase(
          name: 'public_get_encrypted_hit',
          action: () async {
            expect(
              await encrypted.get(existingKey),
              isA<Map<dynamic, dynamic>>(),
            );
          },
        ),
        _DiagnosticCase(
          name: 'native_get_encrypted_hit',
          action: () async {
            expect(await api.get(encrypted.name, existingKey), isNotNull);
          },
        ),
      ];

      for (final diagnostic in cases) {
        await _runIterations(diagnostic.action, 20);
        final elapsed = <int>[];
        for (var sample = 0; sample < samples; sample++) {
          final watch = Stopwatch()..start();
          await _runIterations(diagnostic.action, iterations);
          watch.stop();
          elapsed.add(watch.elapsedMicroseconds);
        }
        elapsed.sort();
        final medianUs = _median(elapsed);
        final result = <String, Object>{
          'operation': diagnostic.name,
          'iterations': iterations,
          'samples': samples,
          'sample_us': elapsed,
          'median_us': medianUs,
          'median_ns_per_op': medianUs * 1000 / iterations,
        };
        // ignore: avoid_print
        print('DXTR_BOX_POINT_READ_DIAGNOSIS ${jsonEncode(result)}');
      }

      await plain.close();
      await encrypted.close();
      await DxtrBox.deleteBox('point_read_plain');
      await DxtrBox.deleteBox('point_read_encrypted');
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_POINT_READ_DIAGNOSIS=1 to run point-read diagnostics.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

final class _DiagnosticCase {
  const _DiagnosticCase({required this.name, required this.action});

  final String name;
  final Future<void> Function() action;
}

Future<void> _runIterations(
  Future<void> Function() action,
  int iterations,
) async {
  for (var i = 0; i < iterations; i++) {
    await action();
  }
}

num _median(List<int> ordered) {
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}
