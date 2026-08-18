import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'box.dart';
import 'native_api.dart';

abstract final class BoxStore {
  static NativeBoxApi _api = const FrbNativeBoxApi();
  static String? _basePath;
  static int _openHandleCount = 0;
  static final Map<String, int> _openHandlesByName = <String, int>{};
  static final Map<String, BoxMetadata> _metadataByName =
      <String, BoxMetadata>{};
  static final Random _watcherRandom = Random.secure();

  static const Set<String> _windowsReservedNames = <String>{
    'CON',
    'PRN',
    'AUX',
    'NUL',
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    'COM5',
    'COM6',
    'COM7',
    'COM8',
    'COM9',
    'LPT1',
    'LPT2',
    'LPT3',
    'LPT4',
    'LPT5',
    'LPT6',
    'LPT7',
    'LPT8',
    'LPT9',
  };

  static final RegExp _unsafeWindowsNameCharacters = RegExp(
    r'[<>:"/\\|?*\x00-\x1F]',
  );

  static bool get isInitialized => _basePath != null;

  /// Package-internal injection point used by tests and alternate engines.
  static void bindNativeApi(NativeBoxApi api) {
    _api = api;
    _basePath = null;
    _openHandleCount = 0;
    _openHandlesByName.clear();
    _metadataByName.clear();
  }

  static Future<void> init({String? path}) async {
    final resolvedPath = p.normalize(
      p.absolute(
        path ??
            p.join((await getApplicationSupportDirectory()).path, 'dxtr_box'),
      ),
    );

    await _api.initDb(resolvedPath);
    if (_basePath != resolvedPath && _openHandleCount == 0) {
      _metadataByName.clear();
    }
    _basePath = resolvedPath;
  }

  static Future<Box> open(
    String name, {
    String? encryptionKey,
    bool lazy = false,
  }) {
    return _open(
      name,
      encryptionKey: encryptionKey,
      lazy: lazy,
      allowMigrationReservation: false,
    );
  }

  static Future<Box> _open(
    String name, {
    String? encryptionKey,
    required bool lazy,
    required bool allowMigrationReservation,
  }) async {
    _ensureInitialized();
    _validateBoxName(name);
    if (lazy) {
      throw UnsupportedError(
        'lazy: true is not implemented. dxtr_box already fetches values from '
        'native storage on demand instead of caching whole-box values in Dart.',
      );
    }

    final migrationReservation = _migrationReservationFile(name);
    if (!allowMigrationReservation && await migrationReservation.exists()) {
      throw StateError(
        'Box "$name" is reserved by an in-progress Hive CE migration.',
      );
    }

    await _api.openBox(name, encryptionKey: encryptionKey);

    // Close the race where a normal open started just before migration acquired
    // the reservation. If migration won destination creation, this handle must
    // not escape to application code and mutate the migration target.
    if (!allowMigrationReservation && await migrationReservation.exists()) {
      await _api.closeBox(name);
      throw StateError(
        'Box "$name" became reserved by a Hive CE migration while opening.',
      );
    }

    final metadata = _metadataByName.putIfAbsent(name, BoxMetadata.new);
    final box = Box.internal(
      name: name,
      watcherId: _newWatcherId(),
      api: _api,
      metadata: metadata,
      onClose: () {
        _openHandleCount -= 1;
        final remaining = (_openHandlesByName[name] ?? 1) - 1;
        if (remaining == 0) {
          _openHandlesByName.remove(name);
        } else {
          _openHandlesByName[name] = remaining;
        }
      },
    );

    try {
      await box.initializeNativeWatch();
      await box.refreshMetadata();
    } catch (_) {
      await box.disposeNativeWatch();
      await _api.closeBox(name);
      rethrow;
    }

    _openHandleCount += 1;
    _openHandlesByName[name] = (_openHandlesByName[name] ?? 0) + 1;
    return box;
  }

  static Future<void> deleteBox(String name) async {
    _ensureInitialized();
    _validateBoxName(name);
    if ((_openHandlesByName[name] ?? 0) > 0) {
      throw StateError('Cannot delete box "$name" while it is open.');
    }
    await _api.deleteBox(name);
    _metadataByName.remove(name);
  }

  /// Explicitly converts an existing plaintext box to encrypted storage.
  ///
  /// All handles for [name] must be closed before migration. The native engine
  /// performs the value rewrite and encryption metadata transition in one redb
  /// write transaction, so callers observe either the original plaintext state
  /// or the fully encrypted state after a successful return.
  static Future<void> encryptBox(
    String name, {
    required String encryptionKey,
  }) async {
    _ensureInitialized();
    _validateBoxName(name);
    if (encryptionKey.isEmpty) {
      throw ArgumentError.value(
        encryptionKey,
        'encryptionKey',
        'Encryption key cannot be empty',
      );
    }
    if ((_openHandlesByName[name] ?? 0) > 0) {
      throw StateError('Cannot encrypt box "$name" while it is open.');
    }

    final api = _api;
    if (api is! NativeEncryptionMigrationApi) {
      throw StateError(
        'The configured dxtr_box native engine does not support encryption migration.',
      );
    }
    final migrationApi = api as NativeEncryptionMigrationApi;
    await migrationApi.encryptBox(name, encryptionKey);
    _metadataByName.remove(name);
  }

  static Future<bool> boxExists(String name) async {
    _ensureInitialized();
    _validateBoxName(name);
    return _api.boxExists(name);
  }

  static File _migrationReservationFile(String name) {
    return File(p.join(_basePath!, '.$name.dxtr.migrating'));
  }

  static String _newWatcherId() {
    final bytes = List<int>.generate(16, (_) => _watcherRandom.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError('Call BoxStore.init() before opening a box.');
    }
  }

  static void _validateBoxName(String name) {
    final windowsStem = name.split('.').first.toUpperCase();
    final invalid =
        name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.endsWith('.') ||
        name.endsWith(' ') ||
        _unsafeWindowsNameCharacters.hasMatch(name) ||
        _windowsReservedNames.contains(windowsStem);
    if (invalid) {
      throw ArgumentError.value(name, 'name', 'Invalid box name');
    }
  }
}

/// Internal migration helpers. This symbol is intentionally not exported from
/// `package:dxtr_box/dxtr_box.dart`.
abstract final class BoxStoreMigrationInternals {
  static Future<Box> openNew(String name, {String? encryptionKey}) async {
    BoxStore._ensureInitialized();
    BoxStore._validateBoxName(name);

    final path = File(p.join(BoxStore._basePath!, '$name.dxtr'));
    final reservation = BoxStore._migrationReservationFile(name);

    if (await path.exists()) {
      throw StateError('Destination dxtr_box "$name" already exists.');
    }

    try {
      await reservation.create(exclusive: true);
    } on FileSystemException {
      if (await reservation.exists()) {
        throw StateError(
          'Destination dxtr_box "$name" is already reserved by a migration.',
        );
      }
      rethrow;
    }

    try {
      // Re-check after acquiring the reservation to close the race with an
      // ordinary open that may have created the destination just beforehand.
      if (await path.exists()) {
        throw StateError('Destination dxtr_box "$name" already exists.');
      }
      await path.create(exclusive: true);
      return await BoxStore._open(
        name,
        encryptionKey: encryptionKey,
        lazy: false,
        allowMigrationReservation: true,
      );
    } catch (_) {
      try {
        await BoxStore._api.closeBox(name);
      } catch (_) {
        // Best-effort close before deleting the reservation we own.
      }
      try {
        await BoxStore._api.deleteBox(name);
      } catch (_) {
        try {
          if (await path.exists()) {
            await path.delete();
          }
        } catch (_) {
          // Preserve the original open failure.
        }
      }
      BoxStore._metadataByName.remove(name);
      await releaseReservation(name);
      rethrow;
    }
  }

  static Future<void> releaseReservation(String name) async {
    final reservation = BoxStore._migrationReservationFile(name);
    try {
      if (await reservation.exists()) {
        await reservation.delete();
      }
    } on FileSystemException {
      // A successful migration must not be reported as failed only because the
      // advisory reservation marker disappeared concurrently.
    }
  }
}

/// Legacy compatibility shim. New code should use [BoxStore].
@Deprecated(
  'Use BoxStore instead. The Dxtr prefix is retained only for source compatibility.',
)
abstract final class DxtrBox {
  static bool get isInitialized => BoxStore.isInitialized;

  static void bindNativeApi(NativeBoxApi api) => BoxStore.bindNativeApi(api);

  static Future<void> init({String? path}) => BoxStore.init(path: path);

  static Future<Box> open(
    String name, {
    String? encryptionKey,
    bool lazy = false,
  }) {
    return BoxStore.open(name, encryptionKey: encryptionKey, lazy: lazy);
  }

  static Future<void> deleteBox(String name) => BoxStore.deleteBox(name);

  static Future<void> encryptBox(
    String name, {
    required String encryptionKey,
  }) => BoxStore.encryptBox(name, encryptionKey: encryptionKey);

  static Future<bool> boxExists(String name) => BoxStore.boxExists(name);
}
