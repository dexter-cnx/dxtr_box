import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';

import 'real_world_workloads.dart';

typedef RealWorldResult = Map<String, Object>;

Future<List<RealWorldResult>> runDxtrRealWorldScenarios({
  required Directory root,
  int catalogRecords = 1000,
  int activityRecords = 2000,
  int samples = 5,
}) async {
  if (catalogRecords <= 0) {
    throw ArgumentError.value(
      catalogRecords,
      'catalogRecords',
      'must be positive',
    );
  }
  if (activityRecords <= 0) {
    throw ArgumentError.value(
      activityRecords,
      'activityRecords',
      'must be positive',
    );
  }
  if (samples <= 0) {
    throw ArgumentError.value(samples, 'samples', 'must be positive');
  }

  final storageRoot = Directory('${root.path}/dxtr')
    ..createSync(recursive: true);
  await BoxStore.init(path: storageRoot.path);

  return <RealWorldResult>[
    await _settingsScenario(samples),
    await _catalogScenario(catalogRecords, samples),
    await _activityScenario(activityRecords, samples),
  ];
}

String encodeRealWorldJsonl(Iterable<RealWorldResult> results) {
  return results.map(jsonEncode).join('\n');
}

Future<RealWorldResult> _settingsScenario(int samples) async {
  const boxName = 'rw_settings';
  final box = await BoxStore.open(boxName);
  try {
    await box.clear();
    final fixture = settingsSessionFixture();
    await box.putAll(fixture);

    final elapsed = <int>[];
    for (var sample = 0; sample < samples; sample++) {
      final stopwatch = Stopwatch()..start();
      for (var iteration = 0; iteration < 200; iteration++) {
        await box.get('theme');
        await box.get('locale');
        await box.get('session');
        await box.put('active_workspace', <String, Object?>{
          'value': 'workspace-${iteration % 5}',
          'updated_at': 1000 + iteration,
        });
      }
      stopwatch.stop();
      elapsed.add(stopwatch.elapsedMicroseconds);
    }

    final activeWorkspace = await box.get('active_workspace') as Map;
    if (activeWorkspace['value'] != 'workspace-4') {
      throw StateError('settings scenario final overwrite validation failed');
    }

    return _result(
      scenario: 'settings_session',
      records: fixture.length,
      operationsPerSample: 800,
      elapsedUs: elapsed,
    );
  } finally {
    await box.close();
    await BoxStore.deleteBox(boxName);
  }
}

Future<RealWorldResult> _catalogScenario(int records, int samples) async {
  const boxName = 'rw_catalog';
  final box = await BoxStore.open(boxName);
  try {
    await box.clear();
    final fixture = catalogWorkspaceFixture(records);
    await box.putAll(fixture);
    final hotKeys = catalogHotKeys(records, limit: 100);
    final deleteKeys = <String>[
      for (var index = 0; index < records; index += 20)
        'item-${index.toString().padLeft(6, '0')}',
    ];

    final elapsed = <int>[];
    for (var sample = 0; sample < samples; sample++) {
      final stopwatch = Stopwatch()..start();
      final batch = await box.getAll(hotKeys);
      for (final key in hotKeys.take(25)) {
        final value = await box.get(key) as Map<String, dynamic>?;
        if (value != null) {
          await box.put(key, <String, Object?>{
            ...value,
            'score': ((value['score'] as int) + 1) % 1000,
          });
        }
      }
      if (sample == samples - 1) {
        await box.deleteAll(deleteKeys);
      }
      stopwatch.stop();
      if (batch.isEmpty) {
        throw StateError('catalog scenario batch read unexpectedly empty');
      }
      elapsed.add(stopwatch.elapsedMicroseconds);
    }

    for (final key in deleteKeys) {
      if (await box.containsKey(key)) {
        throw StateError('catalog scenario delete validation failed for $key');
      }
    }

    return _result(
      scenario: 'catalog_workspace',
      records: records,
      operationsPerSample: hotKeys.length + 25,
      elapsedUs: elapsed,
      extra: <String, Object>{'deleted': deleteKeys.length},
    );
  } finally {
    await box.close();
    await BoxStore.deleteBox(boxName);
  }
}

Future<RealWorldResult> _activityScenario(int records, int samples) async {
  const boxName = 'rw_activity';
  final box = await BoxStore.open(boxName);
  try {
    await box.clear();
    final fixture = activityEventFixture(records);
    await box.putAll(fixture);
    final deleteKeys = activityRetentionDeleteKeys(records);

    final elapsed = <int>[];
    for (var sample = 0; sample < samples; sample++) {
      final stopwatch = Stopwatch()..start();
      for (var index = 0; index < 100; index++) {
        await box.get(
          'event-${(records - 1 - index).toString().padLeft(8, '0')}',
        );
      }
      if (sample == samples - 1) {
        await box.deleteAll(deleteKeys);
      }
      stopwatch.stop();
      elapsed.add(stopwatch.elapsedMicroseconds);
    }

    for (final key in deleteKeys) {
      if (await box.containsKey(key)) {
        throw StateError('activity retention validation failed for $key');
      }
    }
    final retainedKey = 'event-${deleteKeys.length.toString().padLeft(8, '0')}';
    if (!await box.containsKey(retainedKey)) {
      throw StateError('activity retention removed first retained record');
    }

    return _result(
      scenario: 'activity_event',
      records: records,
      operationsPerSample: 100,
      elapsedUs: elapsed,
      extra: <String, Object>{'retention_deleted': deleteKeys.length},
    );
  } finally {
    await box.close();
    await BoxStore.deleteBox(boxName);
  }
}

RealWorldResult _result({
  required String scenario,
  required int records,
  required int operationsPerSample,
  required List<int> elapsedUs,
  Map<String, Object> extra = const <String, Object>{},
}) {
  final ordered = List<int>.from(elapsedUs)..sort();
  return <String, Object>{
    'frontend': 'dart_frb',
    'scenario': scenario,
    'records': records,
    'samples': elapsedUs.length,
    'operations_per_sample': operationsPerSample,
    'elapsed_us': elapsedUs,
    'median_us': ordered[ordered.length ~/ 2],
    'min_us': ordered.first,
    'max_us': ordered.last,
    'build_mode': 'benchmark_harness',
    ...extra,
  };
}
