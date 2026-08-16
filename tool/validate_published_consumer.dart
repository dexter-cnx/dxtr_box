import 'dart:io';

const _supportedPlatforms = <String>{
  'android',
  'ios',
  'macos',
  'linux',
  'windows',
};

Future<void> main(List<String> args) async {
  final platform = _readPlatform(args);
  final root = Directory.current.absolute;
  final buildRoot = Directory('${root.path}/build');
  final stagedPackage =
      Directory('${buildRoot.path}/published-payload/dxtr_box');
  final consumer = Directory('${buildRoot.path}/published-consumer-$platform');

  await _resetDirectory(stagedPackage);
  await _resetDirectory(consumer);

  final rules = _readSimplePubIgnore(File('${root.path}/.pubignore'));
  await _copyPublishedPayload(root, stagedPackage, rules);
  _validateStagedPayload(stagedPackage);

  await _run(
    'flutter',
    <String>[
      'create',
      '--platforms=$platform',
      '--project-name=dxtr_box_consumer',
      '.',
    ],
    workingDirectory: consumer.path,
  );

  _wireConsumerDependency(consumer);
  _wireConsumerApiReference(consumer);

  await _run('flutter', <String>['pub', 'get'],
      workingDirectory: consumer.path);

  switch (platform) {
    case 'android':
      await _run(
        'flutter',
        <String>['build', 'apk', '--debug'],
        workingDirectory: consumer.path,
      );
      break;
    case 'ios':
      await _run(
        'flutter',
        <String>['build', 'ios', '--debug', '--no-codesign'],
        workingDirectory: consumer.path,
      );
      break;
    case 'macos':
      await _run(
        'flutter',
        <String>['build', 'macos', '--debug'],
        workingDirectory: consumer.path,
      );
      break;
    case 'linux':
      await _run(
        'flutter',
        <String>['config', '--enable-linux-desktop'],
        workingDirectory: consumer.path,
      );
      await _run(
        'flutter',
        <String>['build', 'linux', '--debug'],
        workingDirectory: consumer.path,
      );
      break;
    case 'windows':
      await _run(
        'flutter',
        <String>['config', '--enable-windows-desktop'],
        workingDirectory: consumer.path,
      );
      await _run(
        'flutter',
        <String>['build', 'windows', '--debug', '--verbose'],
        workingDirectory: consumer.path,
      );
      break;
  }

  stdout.writeln(
    'DXTR_BOX_PUBLISHED_CONSUMER PASS platform=$platform package=${stagedPackage.path}',
  );
}

String _readPlatform(List<String> args) {
  final argument =
      args.where((value) => value.startsWith('--platform=')).firstOrNull;
  if (argument == null) {
    stderr.writeln(
      'usage: dart run tool/validate_published_consumer.dart --platform=<platform>',
    );
    throw StateError('missing --platform');
  }
  final platform = argument.substring('--platform='.length);
  if (!_supportedPlatforms.contains(platform)) {
    throw ArgumentError.value(platform, 'platform', 'unsupported platform');
  }
  return platform;
}

List<_IgnoreRule> _readSimplePubIgnore(File file) {
  if (!file.existsSync()) {
    throw StateError('.pubignore is required for published-payload validation');
  }

  final rules = <_IgnoreRule>[];
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('!') ||
        line.contains('*') ||
        line.contains('?') ||
        line.contains('[')) {
      throw StateError(
        'PH-04 staging supports explicit file/directory .pubignore rules only; unsupported rule: $line',
      );
    }
    final directoryRule = line.endsWith('/');
    final normalized =
        directoryRule ? line.substring(0, line.length - 1) : line;
    rules.add(_IgnoreRule(normalized, directoryRule));
  }
  return rules;
}

Future<void> _copyPublishedPayload(
  Directory root,
  Directory destination,
  List<_IgnoreRule> rules,
) async {
  Future<void> copyDirectory(Directory source) async {
    await for (final entity in source.list(followLinks: false)) {
      final relative = _relativePath(root.path, entity.path);
      if (_isHidden(relative) || _isIgnored(relative, rules)) {
        continue;
      }

      final targetPath =
          '${destination.path}${Platform.pathSeparator}${_nativePath(relative)}';
      if (entity is Directory) {
        await Directory(targetPath).create(recursive: true);
        await copyDirectory(entity);
      } else if (entity is File) {
        await File(targetPath).parent.create(recursive: true);
        await entity.copy(targetPath);
      } else if (entity is Link) {
        throw StateError(
            'published payload may not contain symlinks: $relative');
      }
    }
  }

  await copyDirectory(root);
}

void _validateStagedPayload(Directory stagedPackage) {
  const required = <String>[
    'pubspec.yaml',
    'README.md',
    'CHANGELOG.md',
    'LICENSE',
    'lib/dxtr_box.dart',
    'rust/Cargo.toml',
    'cargokit',
    'android/build.gradle',
    'ios/dxtr_box.podspec',
    'macos/dxtr_box.podspec',
    'linux/CMakeLists.txt',
    'windows/CMakeLists.txt',
  ];
  for (final path in required) {
    final entityPath =
        '${stagedPackage.path}${Platform.pathSeparator}${_nativePath(path)}';
    if (FileSystemEntity.typeSync(entityPath) ==
        FileSystemEntityType.notFound) {
      throw StateError(
        'published payload is missing required consumer input: $path',
      );
    }
  }

  const forbidden = <String>[
    '.github',
    'benchmark',
    'docs',
    'test',
    'tool',
    'Makefile',
    'flutter_rust_bridge.yaml',
    'rust/tests',
    'rust/target',
  ];
  for (final path in forbidden) {
    final entityPath =
        '${stagedPackage.path}${Platform.pathSeparator}${_nativePath(path)}';
    if (FileSystemEntity.typeSync(entityPath) !=
        FileSystemEntityType.notFound) {
      throw StateError(
          'repository-only path leaked into published payload: $path');
    }
  }

  final pubspec = File('${stagedPackage.path}/pubspec.yaml').readAsStringSync();
  if (RegExp(r'^    path:\s+', multiLine: true).hasMatch(pubspec)) {
    throw StateError(
        'published root pubspec may not contain path-source dependencies');
  }
}

void _wireConsumerDependency(Directory consumer) {
  final pubspecFile = File('${consumer.path}/pubspec.yaml');
  final original = pubspecFile.readAsStringSync();
  final anchor = RegExp(r'dependencies:\r?\n  flutter:');
  if (!anchor.hasMatch(original)) {
    throw StateError(
      'generated consumer pubspec shape changed; dependency anchor not found',
    );
  }
  final lineEnding = original.contains('\r\n') ? '\r\n' : '\n';
  final updated = original.replaceFirst(
    anchor,
    'dependencies:$lineEnding'
    '  dxtr_box:$lineEnding'
    '    path: ../published-payload/dxtr_box$lineEnding'
    '  flutter:',
  );
  pubspecFile.writeAsStringSync(updated);
}

void _wireConsumerApiReference(Directory consumer) {
  File('${consumer.path}/lib/main.dart').writeAsStringSync('''
import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const _ConsumerApp());
}

class _ConsumerApp extends StatelessWidget {
  const _ConsumerApp();

  @override
  Widget build(BuildContext context) {
    final Type publicApiSmoke = DxtrBox;
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Text(publicApiSmoke.toString())),
      ),
    );
  }
}
''');
}

bool _isIgnored(String relative, List<_IgnoreRule> rules) {
  for (final rule in rules) {
    if (relative == rule.path) {
      return true;
    }
    if (rule.directory && relative.startsWith('${rule.path}/')) {
      return true;
    }
  }
  return false;
}

bool _isHidden(String relative) {
  return relative.split('/').any((segment) => segment.startsWith('.'));
}

String _relativePath(String root, String child) {
  final normalizedRoot =
      root.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final normalizedChild = child.replaceAll('\\', '/');
  if (!normalizedChild.startsWith('$normalizedRoot/')) {
    throw StateError('path escaped repository root: $child');
  }
  return normalizedChild.substring(normalizedRoot.length + 1);
}

String _nativePath(String path) => path.replaceAll('/', Platform.pathSeparator);

Future<void> _resetDirectory(Directory directory) async {
  if (directory.existsSync()) {
    await directory.delete(recursive: true);
  }
  await directory.create(recursive: true);
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  stdout.writeln('> $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final exitCode = await process.exitCode;
  if (exitCode != 0) {
    throw ProcessException(executable, arguments, 'command failed', exitCode);
  }
}

class _IgnoreRule {
  const _IgnoreRule(this.path, this.directory);

  final String path;
  final bool directory;
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
