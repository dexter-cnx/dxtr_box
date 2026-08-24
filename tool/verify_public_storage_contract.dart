import 'dart:io';

const _expectedExports = <String>{
  "export 'src/box.dart';",
  "export 'src/box_event.dart';",
  "export 'src/dxtr_box.dart' show BoxStore, DxtrBox;",
  "export 'src/hive_ce_migration.dart';",
  "export 'src/query.dart';",
  "export 'src/query_builder.dart';",
  "export 'src/query_field.dart';",
};

const _expectedRustRootExports = <String>{
  'pub use api::*;',
  'pub use error::DxtrBoxError;',
  'pub use native::{BoxHandle, DxtrBox, IndexDefinition, Record};',
  'pub use native::{QueryBuilder, QueryValue, SortOrder};',
};

const _expectedApiNames = <String>{
  'NativeBoxEventType',
  'NativeBoxEvent',
  'NativeQueryRecord',
  'NativeBatchRecord',
  'NativeIndexDefinition',
  'init_db',
  'open_box',
  'close_box',
  'delete_box',
  'encrypt_box',
  'box_exists',
  'watch_box',
  'unwatch_box',
  'put',
  'put_all',
  'get',
  'contains_key',
  'get_all',
  'delete',
  'delete_all',
  'clear',
  'compact',
  'scan_query',
  'create_index',
  'list_indexes',
  'drop_index',
  'get_all_keys',
  'length',
};

const _storageFormatMarker = 'dxtr_box/1';
const _storageFormatMetaKey = 'format_version';
const _rustIdentity = 'rust_lib_dxtr_box';
const _rustCrateType = 'crate-type = ["cdylib", "staticlib", "rlib"]';
const _queryExport = 'pub use native::{QueryBuilder, QueryValue, SortOrder};';
const _fullCfg = '#[cfg(feature = "full")]';

void main() {
  verifyPublicStorageContract();
  stdout.writeln(
    'DXTR_BOX_CONTRACT PASS exports=${_expectedExports.length} '
    'rust_exports=${_expectedRustRootExports.length} '
    'storage=$_storageFormatMarker',
  );
}

void verifyPublicStorageContract() {
  _verifyPackageIdentity();
  _verifyPublicExports();
  _verifyRustCrateBoundary();
  _verifyStorageFormatIdentity();
}

void _verifyPackageIdentity() {
  final lines = _trimmedLines('pubspec.yaml').toSet();
  const required = <String>{
    'name: dxtr_box',
    "sdk: '>=3.4.0 <4.0.0'",
    "flutter: '>=3.22.0'",
    'flutter_rust_bridge: 2.8.0',
  };
  final missing = required.difference(lines);
  if (missing.isNotEmpty) {
    throw StateError('package contract changed; missing=$missing');
  }
}

void _verifyPublicExports() {
  final exports = _trimmedLines('lib/dxtr_box.dart')
      .where((line) => line.startsWith('export '))
      .toSet();
  _requireExactSet('Dart export boundary', _expectedExports, exports);
}

void _verifyRustCrateBoundary() {
  final cargo = File('rust/Cargo.toml').readAsStringSync();
  final packageLines = _tomlSectionLines(cargo, 'package');
  final libraryLines = _tomlSectionLines(cargo, 'lib');
  const expectedName = 'name = "$_rustIdentity"';

  if (!packageLines.contains(expectedName)) {
    throw StateError('Cargo package identity changed: $expectedName');
  }
  if (!libraryLines.contains(expectedName)) {
    throw StateError('Cargo library identity changed: $expectedName');
  }
  if (!libraryLines.contains(_rustCrateType)) {
    throw StateError('native crate-type contract changed');
  }

  _verifyCargoRequirements(cargo);

  final rootLines = _trimmedLines('rust/src/lib.rs');
  final rootExports = rootLines
      .where((line) => line.startsWith('pub use '))
      .toSet();
  _requireExactSet('Rust root export boundary', _expectedRustRootExports, rootExports);

  final queryIndex = rootLines.indexOf(_queryExport);
  final guarded = queryIndex > 0 && rootLines[queryIndex - 1] == _fullCfg;
  if (!guarded) {
    throw StateError('full-profile cfg must guard the query root export');
  }

  _verifyWildcardApiSurface();
}

void _verifyCargoRequirements(String cargo) {
  final lines = cargo.split('\n').map((line) => line.trim()).toSet();
  const required = <String>{
    'default = ["full"]',
    'redb = "=2.1.0"',
    'flutter_rust_bridge = "=2.8.0"',
  };
  final missing = required.difference(lines);
  if (missing.isNotEmpty) {
    throw StateError('native dependency contract changed; missing=$missing');
  }
}

void _verifyWildcardApiSurface() {
  final names = <String>{};
  for (final line in _trimmedLines('rust/src/api.rs')) {
    final name = _publicApiName(line);
    if (name != null) {
      names.add(name);
    }
  }
  _requireExactSet('api::* public surface', _expectedApiNames, names);
}

String? _publicApiName(String line) {
  for (final prefix in const ['pub enum ', 'pub struct ', 'pub fn ']) {
    if (line.startsWith(prefix)) {
      return line.substring(prefix.length).split(RegExp(r'[^A-Za-z0-9_]')).first;
    }
  }
  return null;
}

void _requireExactSet(String label, Set<String> expected, Set<String> actual) {
  final missing = expected.difference(actual);
  final added = actual.difference(expected);
  if (missing.isNotEmpty || added.isNotEmpty) {
    throw StateError('$label changed; missing=$missing added=$added');
  }
}

List<String> _trimmedLines(String path) {
  return File(path).readAsLinesSync().map((line) => line.trim()).toList();
}

Set<String> _tomlSectionLines(String source, String section) {
  final result = <String>{};
  var inSection = false;

  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      inSection = line == '[$section]';
      continue;
    }
    if (inSection && line.isNotEmpty && !line.startsWith('#')) {
      result.add(line);
    }
  }

  return result;
}

void _verifyStorageFormatIdentity() {
  final source = File('rust/src/db.rs').readAsStringSync();
  final formatPattern = RegExp(
    r'const FORMAT_VERSION: &\[u8\] = b"([^"]+)";',
  );
  final metaKeyPattern = RegExp(
    r'const META_FORMAT_VERSION: &str = "([^"]+)";',
  );
  final format = formatPattern.firstMatch(source)?.group(1);
  final metaKey = metaKeyPattern.firstMatch(source)?.group(1);

  if (format != _storageFormatMarker) {
    throw StateError('durable storage format changed: $format');
  }
  if (metaKey != _storageFormatMetaKey) {
    throw StateError('durable storage metadata key changed: $metaKey');
  }
}
