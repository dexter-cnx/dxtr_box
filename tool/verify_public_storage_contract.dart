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

const _storageFormatMarker = 'dxtr_box/1';
const _storageFormatMetaKey = 'format_version';
const _rustIdentity = 'rust_lib_dxtr_box';
const _rustCrateType = 'crate-type = ["cdylib", "staticlib", "rlib"]';

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
  final pubspec = File('pubspec.yaml').readAsStringSync();
  const required = <String>[
    'name: dxtr_box',
    "sdk: '>=3.4.0 <4.0.0'",
    "flutter: '>=3.22.0'",
    'flutter_rust_bridge: 2.8.0',
  ];

  final missing = required.where((entry) => !pubspec.contains(entry)).toList();
  if (missing.isNotEmpty) {
    throw StateError(
      '1.0 package identity/compatibility contract changed; missing=$missing',
    );
  }
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
    throw StateError(
      'Cargo package identity changed; expected '
      '[package].name = "$_rustIdentity"',
    );
  }
  if (!libraryLines.contains(expectedName)) {
    throw StateError(
      'Cargo library identity changed; expected '
      '[lib].name = "$_rustIdentity"',
    );
  }
  if (!libraryLines.contains(_rustCrateType)) {
    throw StateError('native crate-type contract changed');
  }

  const requiredCargo = <String>[
    'default = ["full"]',
    'redb = "=2.1.0"',
    'flutter_rust_bridge = "=2.8.0"',
  ];
  final missingCargo = requiredCargo
      .where((entry) => !cargo.contains(entry))
      .toList();
  if (missingCargo.isNotEmpty) {
    throw StateError(
      'native profile/dependency contract changed; missing=$missingCargo',
    );
  }

  final rustRootLines = File('rust/src/lib.rs')
      .readAsLinesSync()
      .map((line) => line.trim())
      .toSet();
  final rustRootExports = rustRootLines
      .where((line) => line.startsWith('pub use '))
      .toSet();

  final missingExports = _expectedRustRootExports.difference(rustRootExports);
  final addedExports = rustRootExports.difference(_expectedRustRootExports);
  if (missingExports.isNotEmpty || addedExports.isNotEmpty) {
    throw StateError(
      'Rust root public export boundary changed without a 1.0 contract update; '
      'missing=$missingExports added=$addedExports',
    );
  }

  if (!rustRootLines.contains('#[cfg(feature = "full")]')) {
    throw StateError('full-profile cfg guard unexpectedly missing from Rust root');
  }
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
