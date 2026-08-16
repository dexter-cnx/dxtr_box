import 'dart:async';
import 'dart:io';

import 'package:dxtr_box/src/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('openNew removes its reservation when handle initialization fails',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dxtr_open_new_failure_');
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    final api = _FailingWatchApi();
    DxtrBox.bindNativeApi(api);
    await DxtrBox.init(path: root.path);

    await expectLater(
      DxtrBoxMigrationInternals.openNew('failed-destination'),
      throwsStateError,
    );

    expect(await DxtrBox.boxExists('failed-destination'), isFalse);
    expect(File('${root.path}/failed-destination.dxtr').existsSync(), isFalse);
  });
}

final class _FailingWatchApi implements NativeDxtrApi {
  String? _basePath;
  final Set<String> _boxes = <String>{};
  final Set<String> _open = <String>{};

  @override
  Future<void> initDb(String path) async {
    _basePath = path;
  }

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async {
    _boxes.add(name);
    _open.add(name);
  }

  @override
  Future<void> closeBox(String name) async {
    _open.remove(name);
  }

  @override
  Future<void> deleteBox(String name) async {
    if (_open.contains(name)) {
      throw StateError('cannot delete open box');
    }
    _boxes.remove(name);
    final basePath = _basePath;
    if (basePath != null) {
      final file = File('$basePath/$name.dxtr');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  @override
  Future<bool> boxExists(String name) async => _boxes.contains(name);

  @override
  Future<Stream<NativeWatchEvent>> watchBox(
    String boxName,
    String watcherId,
  ) async {
    if (!_open.contains(boxName)) {
      throw StateError('box is not open');
    }
    throw StateError('injected watch initialization failure');
  }

  @override
  Future<void> unwatchBox(String boxName, String watcherId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(invocation.memberName.toString());
  }
}
