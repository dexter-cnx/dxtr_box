import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';

import 'real_world_workloads.dart';

typedef RealWorldResult = Map<String, Object>;

Future<List<RealWorldResult>> runDxtrRealWorldScenarios({
  required Directory root,
  required String nativeBuildMode,
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
  if (nativeBuildMode.trim().isEmpty) {
    throw ArgumentError.value(
      nativeBuildMode,
      'nativeBuildMode',
      'must identify the loaded native library build mode',
    );
  }

  final storageRoot = Directory('${root.path}/dxtr')
    ..createSync(recursive: true);
  await BoxStore.init(path: storageRoot.path);

  return <RealWorldResult>[
    await _settingsScenario(samples, nativeBuildMode),
    await _catalogScenario(catalogRecords, samples, nativeBuildMode),
    await _activityScenario(activityRecords, samples, nativeBuildMode),
  ];
}

String encodeRealWorldJsonl(Iterable<RealWorldResult> results) {
  return results.map(jsonEncode).join('\n');
}

Future<RealWorldResult> _settingsScenario(
  int samples,
  String nativeBuildMode,
) async {
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
      nativeBuildMode: nativeBuildMode,
    );
  } finally {
    await box.close();
    await BoxStore.deleteBox(boxName);
  }
}

Future<RealWorldResult> _catalogScenario(
  int records,
  int samples,
  String nativeBuildMode,
) async {
  const boxName = 'rw_catalog';
  final box = await BoxStore.open(boxName);
  try {
    await box.clear();
    final fixture = catalogWorkspaceFixture(records);
    await box.putAll(fixture);
    final hotKeys = catalogHotKeys(records, limit: 100);
    final updateKeys = hotKeys.take(25).toList(growable: false);
    final deleteKeys = <String>[
      for (var index = 0; index < records; index += 20)
        'item-${index.toString().padLeft(6, '0')}',
    ];

    final elapsed = <int>[];
    for (var sample = 0; sample < samples; sample++) {
      final stopwatch = Stopwatch()..start();
      final batch = await box.getAll(hotKeys);
      for (final key in updateKeys) {
        final raw = await box.get(key);
        if (raw is Map) {
          final value = Map<String, Object?>.from(raw);
          await box.put(key, <String, Object?>{
            ...value,
            'score': ((value['score'] as int) + 1) % 1000,
          });
        }
      }
      stopwatch.stop();
      elapsed.add(stopwatch.elapsedMicroseconds);

      final actualKeys = batch
          .map((entry) => entry.key)
          .toList(growable: false);
      if (!_sameStrings(actualKeys, hotKeys)) {
        throw StateError('catalog scenario batch ordering validation failed');
      }
      for (var index = 0; index < batch.length; index++) {
        final raw = batch[index].value;
        if (raw is! Map) {
          throw StateError('catalog scenario batch value is not a record');
        }
        final value = Map<String, Object?>.from(raw);
        final expected = fixture[hotKeys[index]]!;
        if (value['id'] != expected['id'] ||
            value['name'] != expected['name']) {
          throw StateError(
            'catalog scenario batch value validation failed for ${hotKeys[index]}',
          );
        }
      }
    }

    await box.deleteAll(deleteKeys);
    for (final key in deleteKeys) {
      if (await box.containsKey(key)) {
        throw StateError('catalog scenario delete validation failed for $key');
      }
    }

    return _result(
      scenario: 'catalog_workspace',
      records: records,
      operationsPerSample: hotKeys.length + (updateKeys.length * 2),
      elapsedUs: elapsed,
      nativeBuildMode: nativeBuildMode,
      extra: <String, Object>{
        'operation_unit': 'logical_records',
        'untimed_deleted': deleteKeys.length,
      },
    );
  } finally {
    await box.close();
    await BoxStore.deleteBox(boxName);
  }
}

Future<RealWorldResult> _activityScenario(
  int records,
  int samples,
  String nativeBuildMode,
) async {
  const boxName = 'rw_activity';
  final box = await BoxStore.open(boxName);
  try {
    await box.clear();
    final fixture = activityEventFixture(records);
    await box.putAll(fixture);
    final deleteKeys = activityRetentionDeleteKeys(records);
    final readCount = records < 100 ? records : 100;

    final elapsed = <int>[];
    for (var sample = 0; sample < samples; sample++) {
      final stopwatch = Stopwatch()..start();
      for (var index = 0; index < readCount; index++) {
        await box.get(
          'event-${(records - 1 - index).toString().padLeft(8, '0')}',
        );
      }
      stopwatch.stop();
      elapsed.add(stopwatch.elapsedMicroseconds);
    }

    await box.deleteAll(deleteKeys);
    for (final key in deleteKeys) {
      if (await box.containsKey(key)) {
        throw StateError('activity retention validation failed for $key');
      }
    }
    final retainedIndex = deleteKeys.length;
    if (retainedIndex < records) {
      final retainedKey = 'event-${retainedIndex.toString().padLeft(8, '0')}';
      if (!await box.containsKey(retainedKey)) {
        throw StateError('activity retention removed first retained record');
      }
    }

    return _result(
      scenario: 'activity_event',
      records: records,
      operationsPerSample: readCount,
      elapsedUs: elapsed,
      nativeBuildMode: nativeBuildMode,
      extra: <String, Object>{
        'operation_unit': 'logical_records',
        'untimed_retention_deleted': deleteKeys.length,
      },
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
  required String nativeBuildMode,
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
    'dart_build_mode': _dartBuildMode(),
    'native_build_mode': nativeBuildMode,
    ...extra,
  };
}

String _dartBuildMode() {
  if (const bool.fromEnvironment('dart.vm.product')) {
    return 'release';
  }
  if (const bool.fromEnvironment('dart.vm.profile')) {
    return 'profile';
  }
  return 'debug';
}

bool _sameStrings(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    return false;
  }
  for (var index = 0; index < actual.length; index++) {
    if (actual[index] != expected[index]) {
      return false;
    }
  }
  return true;
}
