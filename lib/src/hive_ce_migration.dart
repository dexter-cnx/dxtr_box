import 'dart:typed_data';

import 'codec.dart';
import 'dxtr_box.dart';

typedef HiveCeValueConverter = dynamic Function(dynamic value);
typedef HiveCeKeyConverter = String Function(dynamic key);

/// Adapter over an already-open Hive CE box.
///
/// Keeping the adapter callback-based lets dxtr_box preserve its Dart 3.4 /
/// Flutter 3.22 minimum SDK contract without taking a runtime dependency on
/// Hive CE. Applications can wrap their current Hive CE box directly.
final class HiveCeMigrationSource {
  const HiveCeMigrationSource({
    required this.name,
    required bool Function() isOpen,
    required Iterable<dynamic> Function() keys,
    required dynamic Function(dynamic key) get,
  })  : _isOpen = isOpen,
        _keys = keys,
        _get = get;

  final String name;
  final bool Function() _isOpen;
  final Iterable<dynamic> Function() _keys;
  final dynamic Function(dynamic key) _get;

  bool get isOpen => _isOpen();
  Iterable<dynamic> get keys => _keys();
  dynamic get(dynamic key) => _get(key);
}

final class HiveCeMigrationResult {
  const HiveCeMigrationResult({
    required this.sourceName,
    required this.destinationName,
    required this.entriesMigrated,
  });

  final String sourceName;
  final String destinationName;
  final int entriesMigrated;
}

Future<HiveCeMigrationResult> migrateFromHiveCe(
  HiveCeMigrationSource source, {
  required String destinationName,
  String? destinationEncryptionKey,
  HiveCeValueConverter? valueConverter,
  HiveCeKeyConverter? keyConverter,
}) async {
  if (!DxtrBox.isInitialized) {
    throw StateError('Call DxtrBox.init() before migrating a Hive CE box.');
  }
  if (!source.isOpen) {
    throw StateError('Hive CE source box "${source.name}" must be open.');
  }

  final prepared = <String, dynamic>{};
  for (final sourceKey in source.keys) {
    final destinationKey = _convertHiveCeKey(sourceKey, keyConverter);
    if (prepared.containsKey(destinationKey)) {
      throw StateError(
        'Hive CE key collision after conversion: "$destinationKey".',
      );
    }

    final normalized = _normalizeHiveCeValue(
      source.get(sourceKey),
      valueConverter,
    );
    DxtrCodec.encode(normalized);
    prepared[destinationKey] = normalized;
  }

  final destination = await DxtrBoxMigrationInternals.openNew(
    destinationName,
    encryptionKey: destinationEncryptionKey,
  );
  var destinationClosed = false;
  try {
    await destination.putAll(prepared);
    await destination.close();
    destinationClosed = true;
  } catch (_) {
    if (!destinationClosed) {
      await destination.close();
    }
    await DxtrBox.deleteBox(destinationName);
    rethrow;
  } finally {
    await DxtrBoxMigrationInternals.releaseReservation(destinationName);
  }

  return HiveCeMigrationResult(
    sourceName: source.name,
    destinationName: destinationName,
    entriesMigrated: prepared.length,
  );
}

String _convertHiveCeKey(dynamic key, HiveCeKeyConverter? converter) {
  if (converter != null) {
    final converted = converter(key);
    if (converted.isEmpty) {
      throw ArgumentError.value(
        converted,
        'keyConverter',
        'Key cannot be empty',
      );
    }
    return converted;
  }
  if (key is String) {
    return key;
  }
  if (key is int) {
    return '@hive-int:$key';
  }
  throw UnsupportedError(
    'Unsupported Hive CE key type ${key.runtimeType}. '
    'Use keyConverter to map it to a String.',
  );
}

dynamic _normalizeHiveCeValue(
  dynamic value,
  HiveCeValueConverter? converter,
) {
  if (value == null ||
      value is bool ||
      value is int ||
      value is double ||
      value is String ||
      value is Uint8List ||
      value is DateTime) {
    return value;
  }
  if (value is List) {
    return value
        .map((item) => _normalizeHiveCeValue(item, converter))
        .toList(growable: false);
  }
  if (value is Map) {
    if (value.keys.every((key) => key is String)) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key as String: _normalizeHiveCeValue(entry.value, converter),
      };
    }
    return _convertUnsupportedHiveCeValue(value, converter);
  }
  return _convertUnsupportedHiveCeValue(value, converter);
}

dynamic _convertUnsupportedHiveCeValue(
  dynamic value,
  HiveCeValueConverter? converter,
) {
  if (converter == null) {
    throw UnsupportedError(
      'Unsupported Hive CE value type ${value.runtimeType}. '
      'Provide valueConverter for custom or unsupported values.',
    );
  }
  final converted = converter(value);
  if (identical(converted, value)) {
    throw StateError(
      'valueConverter returned the original unsupported '
      '${value.runtimeType} instance.',
    );
  }
  return _normalizeHiveCeValue(converted, null);
}
