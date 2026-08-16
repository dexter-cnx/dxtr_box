import 'dart:typed_data';

import 'package:hive_ce/hive.dart' as hive;

import 'codec.dart';
import 'dxtr_box.dart';

typedef HiveCeValueConverter = dynamic Function(dynamic value);
typedef HiveCeKeyConverter = String Function(dynamic key);

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
  hive.Box<dynamic> source, {
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
  if (await DxtrBox.boxExists(destinationName)) {
    throw StateError(
      'Destination dxtr_box "$destinationName" already exists.',
    );
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

  var destinationOpened = false;
  try {
    final destination = await DxtrBox.open(
      destinationName,
      encryptionKey: destinationEncryptionKey,
    );
    destinationOpened = true;
    try {
      await destination.putAll(prepared);
    } finally {
      await destination.close();
    }
  } catch (_) {
    if (destinationOpened && await DxtrBox.boxExists(destinationName)) {
      await DxtrBox.deleteBox(destinationName);
    }
    rethrow;
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
      throw ArgumentError.value(converted, 'keyConverter', 'Key cannot be empty');
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
