import 'dart:typed_data';

import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;

/// Stable package-internal wire format.
///
/// Tagged values preserve Dart types that MessagePack does not model directly.
abstract final class BoxCodec {
  static Uint8List encode(dynamic value) {
    final normalized = _toWire(value);
    return msgpack.serialize(normalized);
  }

  static dynamic decode(List<int> bytes) {
    final input = bytes is Uint8List &&
            bytes.offsetInBytes == 0 &&
            bytes.lengthInBytes == bytes.buffer.lengthInBytes
        ? bytes
        : Uint8List.fromList(bytes);
    final decoded = msgpack.deserialize(input);
    return _fromWire(decoded);
  }

  static dynamic _toWire(dynamic value) {
    if (value == null ||
        value is bool ||
        value is int ||
        value is double ||
        value is String) {
      return value;
    }
    if (value is Uint8List) {
      return <dynamic>['@dxtr:bytes', value];
    }
    if (value is DateTime) {
      return <dynamic>['@dxtr:datetime', value.toUtc().microsecondsSinceEpoch];
    }
    if (value is List) {
      return <dynamic>[
        '@dxtr:list',
        value.map(_toWire).toList(growable: false),
      ];
    }
    if (value is Map) {
      final entries = <dynamic>[];
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw ArgumentError.value(value, 'value', 'Map keys must be String');
        }
        entries.add(<dynamic>[entry.key, _toWire(entry.value)]);
      }
      return <dynamic>['@dxtr:map', entries];
    }
    throw ArgumentError.value(
      value,
      'value',
      'Unsupported type ${value.runtimeType}. Supported: null, bool, int, '
          'double, String, List, Map<String, dynamic>, Uint8List, DateTime.',
    );
  }

  static dynamic _fromWire(dynamic value) {
    if (value is! List || value.length != 2 || value.first is! String) {
      return value;
    }
    final tag = value[0] as String;
    final payload = value[1];
    switch (tag) {
      case '@dxtr:bytes':
        return payload is Uint8List
            ? payload
            : Uint8List.fromList(List<int>.from(payload as List));
      case '@dxtr:datetime':
        return DateTime.fromMicrosecondsSinceEpoch(payload as int, isUtc: true);
      case '@dxtr:list':
        return (payload as List).map(_fromWire).toList(growable: false);
      case '@dxtr:map':
        return <String, dynamic>{
          for (final pair in payload as List)
            (pair as List)[0] as String: _fromWire(pair[1]),
        };
      default:
        return value;
    }
  }
}

/// Legacy package-internal compatibility shim. New code uses [BoxCodec].
@Deprecated('Use BoxCodec instead.')
abstract final class DxtrCodec {
  static Uint8List encode(dynamic value) => BoxCodec.encode(value);

  static dynamic decode(List<int> bytes) => BoxCodec.decode(bytes);
}
