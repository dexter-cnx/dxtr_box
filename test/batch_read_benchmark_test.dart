// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled = Platform.environment['DXTR_BOX_BATCH_READ_BENCHMARK'] == '1';

  test('0.5 PR3 batch read matrix', () async {
    if (!enabled) {
      return;
    }

    DxtrBox.bindNativeApi(const FrbNativeDxtrApi());
    final dir = await Directory.systemTemp.createTemp('dxtr_box_batch_bench_');
    addTearDown(() => dir.delete(recursive: true));
    await DxtrBox.init(path: dir.path);
    final box = await DxtrBox.open('batch-bench');

    final entries = <String, dynamic>{
      for (var i = 0; i < 1000; i++)
        'k$i': <String, dynamic>{'id': i, 'value': 'v$i'},
    };
    await box.putAll(entries);

    for (final size in <int>[10, 100, 1000]) {
      final keys = List<String>.generate(size, (i) => 'k$i', growable: false);
      final batch = await _medianMicros(() async {
        final result = await box.getAll(keys);
        if (result.length != size) {
          throw StateError('batch result mismatch');
        }
      });
      final independent = await _medianMicros(() async {
        for (final key in keys) {
          if (await box.get(key) == null) {
            throw StateError('missing independent get');
          }
        }
      });
      print(
        'DXTR_BOX_BATCH_READ {"keys":$size,"batch_us":$batch,'
        '"independent_us":$independent}',
      );
    }

    await box.close();
  });
}

Future<double> _medianMicros(Future<void> Function() body) async {
  const samples = 5;
  final values = <double>[];
  for (var sample = 0; sample < samples; sample++) {
    final stopwatch = Stopwatch()..start();
    await body();
    stopwatch.stop();
    values.add(stopwatch.elapsedMicroseconds.toDouble());
  }
  values.sort();
  return values[values.length ~/ 2];
}
