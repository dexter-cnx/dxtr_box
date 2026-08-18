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
    BoxStore.bindNativeApi(api);
    await BoxStore.init(path: root.path);

    await expectLater(
      BoxStoreMigrationInternals.openNew('failed-destination'),
      throwsStateError,
    );

    expect(await BoxStore.boxExists('failed-destination'), isFalse);
    expect(File('${root.path}/failed-destination.dxtr').existsSync(), isFalse);
    expect(
      File('${root.path}/.failed-destination.dxtr.migrating').existsSync(),
      isFalse,
    );
  });

  test('ordinary open is rejected while migration reservation is active',
      () async {
    final root =
        await Directory.systemTemp.createTemp('dxtr_open_new_reserved_');
    addTearDown(() async {
      if (root.existsSync()) {
        await root.delete(recursive: true);
      }
    });

    final api = _SuccessfulApi();
    BoxStore.bindNativeApi(api);
    await BoxStore.init(path: root.path);

    final migrationBox =
        await BoxStoreMigrationInternals.openNew('reserved-destination');

    await expectLater(
      BoxStore.open('reserved-destination'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('reserved'),
        ),
      ),
    );

    await migrationBox.close();
    await BoxStoreMigrationInternals.releaseReservation('reserved-destination');

    final reopened = await BoxStore.open('reserved-destination');
    await reopened.close();
  });
}

class _SuccessfulApi implements NativeBoxApi {
  String? basePath;
  final Set<String> boxes = <String>{};
  final Set<String> open = <String>{};

  @override
  Future<void> initDb(String path) async {
    basePath = path;
  }

  @override
  Future<void> openBox(String name, {String? encryptionKey}) async {
    boxes.add(name);
    open.add(name);
  }

  @override
  Future<void> closeBox(String name) async {
    open.remove(name);
  }

  @override
  Future<void> deleteBox(String name) async {
    if (open.contains(name)) {
      throw StateError('cannot delete open box');
    }
    boxes.remove(name);
    final path = basePath;
    if (path != null) {
      final file = File('$path/$name.dxtr');
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  }

  @override
  Future<bool> boxExists(String name) async => boxes.contains(name);

  @override
  Future<Stream<NativeWatchEvent>> watchBox(
    String boxName,
    String watcherId,
  ) async {
    if (!open.contains(boxName)) {
      throw StateError('box is not open');
    }
    return const Stream<NativeWatchEvent>.empty();
  }

  @override
  Future<void> unwatchBox(String boxName, String watcherId) async {}

  @override
  Future<List<String>> getAllKeys(String boxName) async => const <String>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(invocation.memberName.toString());
  }
}

final class _FailingWatchApi extends _SuccessfulApi {
  @override
  Future<Stream<NativeWatchEvent>> watchBox(
    String boxName,
    String watcherId,
  ) async {
    if (!open.contains(boxName)) {
      throw StateError('box is not open');
    }
    throw StateError('injected watch initialization failure');
  }
}
