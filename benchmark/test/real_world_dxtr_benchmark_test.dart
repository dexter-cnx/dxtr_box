import 'dart:io';

import 'package:dxtr_box_benchmark/real_world_dxtr_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final enabled = Platform.environment['DXTR_BOX_REAL_WORLD'] == '1';
  final catalogRecords = int.tryParse(
        Platform.environment['DXTR_BOX_REAL_WORLD_CATALOG'] ?? '',
      ) ??
      1000;
  final activityRecords = int.tryParse(
        Platform.environment['DXTR_BOX_REAL_WORLD_ACTIVITY'] ?? '',
      ) ??
      2000;
  final samples = int.tryParse(
        Platform.environment['DXTR_BOX_REAL_WORLD_SAMPLES'] ?? '',
      ) ??
      5;
  final nativeBuildMode =
      Platform.environment['DXTR_BOX_NATIVE_BUILD_MODE']?.trim() ?? '';

  test(
    'Dart/FRB real-world workload runner emits validated JSONL evidence',
    () async {
      if (nativeBuildMode.isEmpty) {
        throw StateError(
          'DXTR_BOX_NATIVE_BUILD_MODE must identify the loaded native build.',
        );
      }

      final root = await Directory.systemTemp.createTemp(
        'dxtr_box_real_world_',
      );
      addTearDown(() async {
        if (root.existsSync()) {
          await root.delete(recursive: true);
        }
      });

      final results = await runDxtrRealWorldScenarios(
        root: root,
        nativeBuildMode: nativeBuildMode,
        catalogRecords: catalogRecords,
        activityRecords: activityRecords,
        samples: samples,
      );

      expect(results, hasLength(3));
      expect(
        results.map((result) => result['scenario']),
        containsAll(<String>[
          'settings_session',
          'catalog_workspace',
          'activity_event',
        ]),
      );
      for (final result in results) {
        expect(result['frontend'], 'dart_frb');
        expect(result['samples'], samples);
        expect(result['median_us'], isA<int>());
        expect(result['dart_build_mode'], anyOf('debug', 'profile', 'release'));
        expect(result['native_build_mode'], nativeBuildMode);
      }

      for (final line in encodeRealWorldJsonl(results).split('\n')) {
        // Machine-readable evidence consumed by CI artifact extraction in PR4.
        // ignore: avoid_print
        print('DXTR_BOX_REAL_WORLD $line');
      }
    },
    skip: enabled ? false : 'Set DXTR_BOX_REAL_WORLD=1 to run this benchmark.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
