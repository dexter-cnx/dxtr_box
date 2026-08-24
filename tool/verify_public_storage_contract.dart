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

const _expectedApiDeclarations = <String>{
  'pub enum NativeBoxEventType {',
  'pub struct NativeBoxEvent {',
  'pub struct NativeQueryRecord {',
  'pub struct NativeBatchRecord {',
  'pub struct NativeIndexDefinition {',
  'pub fn init_db(path: String) -> Result<(), String> {',
  'pub fn open_box(name: String, encryption_key: Option<String>) -> Result<(), String> {',
  'pub fn close_box(name: String) -> Result<(), String> {',
  'pub fn delete_box(name: String) -> Result<(), String> {',
  'pub fn encrypt_box(name: String, encryption_key: String) -> Result<(), String> {',
  'pub fn box_exists(name: String) -> Result<bool, String> {',
  'pub fn watch_box(',
  'pub fn unwatch_box(box_name: String, watcher_id: String) -> Result<(), String> {',
  'pub fn put(box_name: String, key: String, value: Vec<u8>) -> Result<(), String> {',
  'pub fn put_all(box_name: String, entries: Vec<(String, Vec<u8>)>) -> Result<(), String> {',
  'pub fn get(box_name: String, key: String) -> Result<Option<Vec<u8>>, String> {',
  'pub fn contains_key(box_name: String, key: String) -> Result<bool, String> {',
  'pub fn get_all(box_name: String, keys: Vec<String>) -> Result<Vec<NativeBatchRecord>, String> {',
  'pub fn delete(box_name: String, key: String) -> Result<(), String> {',
  'pub fn delete_all(box_name: String, keys: Vec<String>) -> Result<Vec<String>, String> {',
  'pub fn clear(box_name: String) -> Result<(), String> {',
  'pub fn compact(box_name: String) -> Result<bool, String> {',
  'pub fn scan_query(',
  'pub fn create_index(box_name: String, name: String, field: String) -> Result<(), String> {',
  'pub fn list_indexes(box_name: String) -> Result<Vec<NativeIndexDefinition>, String> {',
  'pub fn drop_index(box_name: String, name: String) -> Result<bool, String> {',
  'pub fn get_all_keys(box_name: String) -> Result<Vec<String>, String> {',
  'pub fn length(box_name: String) -> Result<u64, String> {',
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
  final pubspecLines = _trimmedLines('pubspec.yaml').toSet();
  const required = <String>{
    'name: dxtr_box',
    "sdk: '>=3.4.0 <4.0.0'",
    "flutter: '>=3.22.0'",
    'flutter_rust_bridge: 2.8.0',
  };
  final missing = required.difference(pubspecLines);
  if (missing.isNotEmpty) {
    throw StateError(
      '1.0 package identity/compatibility contract changed; missing=$missing',
    );
  }
}

void _verifyPublicExports() {
  final exports = _trimmedLines('lib/dxtr_box.dart')
      .where((line) => line.startsWith('export '))
      .toSet();
  final missing = _expectedExports.difference(exports);
  final added = exports.difference(_expectedExports);
  if (missing.isNotEmpty || added.isNotEmpty) {
    throw StateError(
      'public export boundary changed without a 1.0 contract update; '
      'missing=$missing added=$added',
    );
  }
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

  final rustRootLines = _trimmedLines('rust/src/lib.rs');
  final rustRootExports = rustRootLines
      .where((line) => line.startsWith('pub use '))
      .toSet();
  final missingExports = _expectedRustRootExports.difference(rustRootExports);
  final addedExports = rustRootExports.difference(_expectedRustRootExports);
  if (missingExports.isNotEmpty || addedExports.isNotEmpty) {
    throw StateError(
      'Rust root public export boundary changed; '
      'missing=$missingExports added=$addedExports',
    );
  }

  final queryIndex = rustRootLines.indexOf(_queryExport);
  if (queryIndex <= 0 || rustRootLines[queryIndex - 1] != _fullCfg) {
    throw StateError('full-profile cfg must guard the query root export');
  }

  _verifyWildcardApiSurface();
}

void _verifyCargoRequirements(String cargo) {
  const required = <String>{
    'default = ["full"]',
    'redb = "=2.1.0"',
    'flutter_rust_bridge = "=2.8.0"',
  };
  final cargoLines = cargo.split('\n').map((line) => line.trim()).toSet();
  final missing = required.difference(cargoLines);
  if (missing.isNotEmpty) {
    throw StateError(
      'native profile/dependency contract changed; missing=$missing',
    );
  }
}

void _verifyWildcardApiSurface() {
  final apiLines = _trimmedLines('rust/src/api.rs');
  final declarations = apiLines.where(_isPublicApiDeclaration).toSet();
  final missing = _expectedApiDeclarations.difference(declarations);
  final added = declarations.difference(_expectedApiDeclarations);
  if (missing.isNotEmpty || added.isNotEmpty) {
    throw StateError(
      'api::* public surface changed; missing=$missing added=$added',
    );
  }
}

bool _isPublicApiDeclaration(String line) {
  return line.startsWith('pub enum ') ||
      line.startsWith('pub struct ') ||
      line.startsWith('pub fn ');
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
      'define compatibility/migration behavior and update the 1.0 contract '
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
