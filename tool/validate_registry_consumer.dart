import 'dart:convert';
import 'dart:io';

const _supportedPlatforms = <String>{
  'android',
  'ios',
  'macos',
  'linux',
  'windows',
};

Future<void> main(List<String> args) async {
  final platform = _readArgument(args, '--platform=');
  final version = _readArgument(args, '--version=');
  if (!_supportedPlatforms.contains(platform)) {
    throw ArgumentError.value(platform, 'platform', 'unsupported platform');
  }

  final root = Directory.current.absolute;
  final consumer = Directory('${root.path}/build/registry-consumer-$platform');
  final evidenceDirectory = Directory('${root.path}/build/registry-evidence');

  await _resetDirectory(consumer);
  await evidenceDirectory.create(recursive: true);

  await _run(
    'flutter',
    <String>[
      'create',
      '--platforms=$platform',
      '--project-name=dxtr_box_registry_consumer',
      '.',
    ],
    workingDirectory: consumer.path,
  );
  await _run(
    'flutter',
    <String>['pub', 'add', 'dxtr_box:$version'],
    workingDirectory: consumer.path,
  );

  _wireConsumerApiReference(consumer);
  final packageRoot = _verifyHostedResolution(consumer, version);

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
        <String>['build', 'windows', '--debug'],
        workingDirectory: consumer.path,
      );
      break;
  }

  final flutterVersion = await _capture(
    'flutter',
    const <String>['--version', '--machine'],
    workingDirectory: consumer.path,
  );
  final evidence = <String, Object>{
    'package': 'dxtr_box',
    'version': version,
    'platform': platform,
    'source': 'hosted-registry',
    'package_root': packageRoot,
    'flutter': jsonDecode(flutterVersion),
  };
  final evidenceFile = File(
    '${evidenceDirectory.path}${Platform.pathSeparator}$platform.json',
  );
  evidenceFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(evidence),
  );

  stdout.writeln(
    'DXTR_BOX_REGISTRY_CONSUMER PASS platform=$platform version=$version root=$packageRoot',
  );
}

String _readArgument(List<String> args, String prefix) {
  for (final argument in args) {
    if (argument.startsWith(prefix)) {
      final value = argument.substring(prefix.length).trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
  }
  throw ArgumentError('missing required argument $prefix<value>');
}

String _verifyHostedResolution(Directory consumer, String version) {
  final file = File('${consumer.path}/.dart_tool/package_config.json');
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final packages = decoded['packages'] as List<dynamic>;
  final package = packages
      .cast<Map<String, dynamic>>()
      .singleWhere((entry) => entry['name'] == 'dxtr_box');
  final rootUri = package['rootUri'] as String;
  final normalized = rootUri.replaceAll('\\', '/');
  if (!normalized.contains('/hosted/') ||
      !normalized.contains('dxtr_box-$version')) {
    throw StateError(
      'dxtr_box did not resolve from hosted registry at exact version $version: $rootUri',
    );
  }
  return rootUri;
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
    final Type boxStoreType = BoxStore;
    final Type compatibilityShimType = DxtrBox;
    final query = BoxQueryBuilder.where('profile.age')
        .gte(18)
        .orderBy('profile.name')
        .limit(20)
        .build();
    final index = IndexDefinition(name: 'by-age', field: 'profile.age');
    const Future<HiveCeMigrationResult> Function(
      HiveCeMigrationSource, {
      required String destinationName,
      String? destinationEncryptionKey,
      HiveCeValueConverter? valueConverter,
      HiveCeKeyConverter? keyConverter,
    }) migration = migrateFromHiveCe;

    final smoke = <Object>[
      boxStoreType,
      compatibilityShimType,
      query,
      index,
      migration,
    ];
    return MaterialApp(
      home: Scaffold(
        body: Center(child: Text(smoke.join('|'))),
      ),
    );
  }
}
''');
}

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

Future<String> _capture(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout.toString().trim();
}
