import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/codec.dart';
import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:dxtr_box/src/rust/api.dart' as frb;
import 'package:flutter_test/flutter_test.dart';

const _defaultIterations = 5000;
const _defaultSamples = 7;

void main() {
  final enabled = Platform.environment['DXTR_BOX_SYNC_GET_EXPERIMENT'] == '1';
  final iterations = int.tryParse(
        Platform.environment['DXTR_BOX_SYNC_GET_ITERATIONS'] ?? '',
      ) ??
      _defaultIterations;
  final samples = int.tryParse(
        Platform.environment['DXTR_BOX_SYNC_GET_SAMPLES'] ?? '',
      ) ??
      _defaultSamples;

  test(
    'measures Flutter Future overhead around synchronous FRB get',
    () async {
      expect(iterations, greaterThan(0));
      expect(samples, greaterThan(0));

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_sync_get_experiment_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      const api = FrbNativeBoxApi();
      BoxStore.bindNativeApi(api);
      await BoxStore.init(path: root.path);

      const boxName = 'sync_get_experiment';
      final box = await BoxStore.open(boxName);
      try {
        await box.clear();
        await box.put('small_map', <String, Object?>{
          'id': 777,
          'name': 'record-777',
          'active': true,
          'tags': <String>['dxtr', 'flutter', 'sync-get'],
        });

        const key = 'small_map';
        final encoded = await api.get(boxName, key);
        expect(encoded, isNotNull);
        expect(BoxCodec.decode(encoded!), isA<Map<dynamic, dynamic>>());

        // Warm all paths before timing.
        for (var i = 0; i < 100; i++) {
          await box.get(key);
          await api.get(boxName, key);
          final raw = frb.get_(boxName: boxName, key: key);
          expect(raw, isNotNull);
          BoxCodec.decode(raw!);
        }

        final publicAsync = await _measureAsync(
          name: 'public_box_get_async',
          samples: samples,
          iterations: iterations,
          action: () async {
            final value = await box.get(key);
            if (value == null) throw StateError('unexpected miss');
          },
        );

        final adapterAsync = await _measureAsync(
          name: 'native_adapter_get_async',
          samples: samples,
          iterations: iterations,
          action: () async {
            final value = await api.get(boxName, key);
            if (value == null) throw StateError('unexpected miss');
          },
        );

        final rawSync = _measureSync(
          name: 'frb_raw_get_sync',
          samples: samples,
          iterations: iterations,
          action: () {
            final value = frb.get_(boxName: boxName, key: key);
            if (value == null) throw StateError('unexpected miss');
          },
        );

        final syncDecode = _measureSync(
          name: 'frb_get_sync_plus_decode',
          samples: samples,
          iterations: iterations,
          action: () {
            final value = frb.get_(boxName: boxName, key: key);
            if (value == null) throw StateError('unexpected miss');
            final decoded = BoxCodec.decode(value);
            if (decoded == null) throw StateError('unexpected null decode');
          },
        );

        for (final result in <Map<String, Object>>[
          publicAsync,
          adapterAsync,
          rawSync,
          syncDecode,
        ]) {
          // ignore: avoid_print
          print('DXTR_BOX_SYNC_GET_EXPERIMENT ${jsonEncode(result)}');
        }

        final publicNs = publicAsync['median_ns_per_op'] as num;
        final syncDecodeNs = syncDecode['median_ns_per_op'] as num;
        final adapterNs = adapterAsync['median_ns_per_op'] as num;
        final rawSyncNs = rawSync['median_ns_per_op'] as num;

        // Informational ratios only: benchmark noise must not fail CI.
        // ignore: avoid_print
        print(
          'DXTR_BOX_SYNC_GET_RATIO ${jsonEncode(<String, Object>{
            'public_vs_sync_decode': publicNs / syncDecodeNs,
            'adapter_async_vs_raw_sync': adapterNs / rawSyncNs,
          })}',
        );
      } finally {
        await box.close();
        await BoxStore.deleteBox(boxName);
      }
    },
    skip: enabled
        ? false
        : 'Set DXTR_BOX_SYNC_GET_EXPERIMENT=1 to run sync-get benchmark.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<Map<String, Object>> _measureAsync({
  required String name,
  required int samples,
  required int iterations,
  required Future<void> Function() action,
}) async {
  final elapsed = <int>[];
  for (var sample = 0; sample < samples; sample++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await action();
    }
    watch.stop();
    elapsed.add(watch.elapsedMicroseconds);
  }
  return _result(name, elapsed, iterations, samples);
}

Map<String, Object> _measureSync({
  required String name,
  required int samples,
  required int iterations,
  required void Function() action,
}) {
  final elapsed = <int>[];
  for (var sample = 0; sample < samples; sample++) {
    final watch = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      action();
    }
    watch.stop();
    elapsed.add(watch.elapsedMicroseconds);
  }
  return _result(name, elapsed, iterations, samples);
}

Map<String, Object> _result(
  String name,
  List<int> elapsed,
  int iterations,
  int samples,
) {
  elapsed.sort();
  final medianUs = _median(elapsed);
  return <String, Object>{
    'operation': name,
    'iterations': iterations,
    'samples': samples,
    'sample_us': elapsed,
    'median_us': medianUs,
    'median_ns_per_op': medianUs * 1000 / iterations,
  };
}

num _median(List<int> ordered) {
  final middle = ordered.length ~/ 2;
  if (ordered.length.isOdd) return ordered[middle];
  return (ordered[middle - 1] + ordered[middle]) / 2;
}
