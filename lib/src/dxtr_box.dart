import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'box.dart';
import 'native_api.dart';

abstract final class DxtrBox {
  static NativeDxtrApi _api = const FrbNativeDxtrApi();
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
  static void bindNativeApi(NativeDxtrApi api) {
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
  }) async {
    _ensureInitialized();
    _validateBoxName(name);
    if (lazy) {
      throw UnsupportedError(
        'lazy: true is not implemented. dxtr_box already fetches values from '
        'native storage on demand instead of caching whole-box values in Dart.',
      );
    }
    await _api.openBox(name, encryptionKey: encryptionKey);

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
    await api.encryptBox(name, encryptionKey);
    _metadataByName.remove(name);
  }

  static Future<bool> boxExists(String name) async {
    _ensureInitialized();
    _validateBoxName(name);
    return _api.boxExists(name);
  }

  static String _newWatcherId() {
    final bytes = List<int>.generate(16, (_) => _watcherRandom.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  static void _ensureInitialized() {
    if (!isInitialized) {
      throw StateError('Call DxtrBox.init() before opening a box.');
    }
  }

  static void _validateBoxName(String name) {
    final windowsStem = name.split('.').first.toUpperCase();
    final invalid = name.isEmpty ||
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
