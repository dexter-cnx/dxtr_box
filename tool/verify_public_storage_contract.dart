import 'dart:io';

const _expectedExports = <String>{
  "export 'src/box.dart';",
  "export 'src/box_event.dart';",
  "export 'src/dxtr_box.dart' show DxtrBox;",
  "export 'src/hive_ce_migration.dart';",
  "export 'src/query.dart';",
};

const _storageFormatMarker = 'dxtr_box/1';
const _storageFormatMetaKey = 'format_version';

void main() {
  _verifyPublicExports();
  _verifyStorageFormatIdentity();
  stdout.writeln(
    'DXTR_BOX_CONTRACT PASS exports=${_expectedExports.length} '
    'storage=$_storageFormatMarker',
  );
}

void _verifyPublicExports() {
  final entrypoint = File('lib/dxtr_box.dart').readAsLinesSync();
  final exports = entrypoint
      .map((line) => line.trim())
      .where((line) => line.startsWith('export '))
      .toSet();

  if (exports.length != _expectedExports.length ||
      !exports.containsAll(_expectedExports)) {
    final missing = _expectedExports.difference(exports);
    final added = exports.difference(_expectedExports);
    throw StateError(
      'public export boundary changed without a PH-05 contract update; '
      'missing=$missing added=$added',
    );
  }
}

void _verifyStorageFormatIdentity() {
  final dbSource = File('rust/src/db.rs').readAsStringSync();
  final formatPattern = RegExp(
    r'const FORMAT_VERSION: &\[u8\] = b"([^"]+)";',
  );
  final metaKeyPattern = RegExp(
    r'const META_FORMAT_VERSION: &str = "([^"]+)";',
  );

  final format = formatPattern.firstMatch(dbSource)?.group(1);
  final metaKey = metaKeyPattern.firstMatch(dbSource)?.group(1);

  if (format != _storageFormatMarker) {
    throw StateError(
      'durable storage format changed from $_storageFormatMarker to $format; '
      'define compatibility/migration behavior and update the PH-05 contract '
      'in the same reviewed change',
    );
  }
  if (metaKey != _storageFormatMetaKey) {
    throw StateError(
      'durable storage format metadata key changed from '
      '$_storageFormatMetaKey to $metaKey',
    );
  }
}
