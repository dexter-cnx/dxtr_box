import 'dart:io';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final cargo = File('rust/Cargo.toml').readAsStringSync();

  final dartVersion = _firstMatch(
    pubspec,
    RegExp(r'^version:\s*([^\s]+)\s*$', multiLine: true),
    'pubspec.yaml version',
  );
  final rustVersion = _firstMatch(
    cargo,
    RegExp(r'^version\s*=\s*"([^"]+)"\s*$', multiLine: true),
    'rust/Cargo.toml package version',
  );
  final crateName = _firstMatch(
    cargo,
    RegExp(r'^name\s*=\s*"([^"]+)"\s*$', multiLine: true),
    'rust/Cargo.toml package name',
  );

  if (crateName != 'rust_lib_dxtr_box') {
    stderr.writeln(
      'Unexpected Rust crate name: $crateName (expected rust_lib_dxtr_box)',
    );
    exitCode = 1;
    return;
  }

  if (dartVersion != rustVersion) {
    stderr.writeln(
      'Package version mismatch: dxtr_box=$dartVersion, '
      'rust_lib_dxtr_box=$rustVersion',
    );
    exitCode = 1;
    return;
  }

  if (!File('LICENSE').existsSync()) {
    stderr.writeln('Root LICENSE is missing; rust/Cargo.toml references ../LICENSE.');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Rust crate publication metadata aligned: '
    'rust_lib_dxtr_box $rustVersion / dxtr_box $dartVersion',
  );
}

String _firstMatch(String input, RegExp pattern, String label) {
  final match = pattern.firstMatch(input);
  if (match == null) {
    stderr.writeln('Unable to read $label.');
    exit(1);
  }
  return match.group(1)!;
}
