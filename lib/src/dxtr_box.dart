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

  static const Set<String> _windowsReservedNames = <String>{
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
  };

  static final RegExp _unsafeWindowsNameCharacters =
      RegExp(r'[<>:"/\\|?*\x00-\x1F]');

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
        path ?? p.join((await getApplicationSupportDirectory()).path, 'dxtr_box'),
      ),
    );

    if (_basePath != null && _basePath != resolvedPath && _openHandleCount > 0) {
      throw StateError(
        'Cannot change the dxtr_box base path while boxes are open.',
      );
    }

    await _api.initDb(resolvedPath);
    if (_basePath != resolvedPath) {
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
    await _api.openBox(name, encryptionKey: encryptionKey);

    final metadata = _metadataByName.putIfAbsent(name, BoxMetadata.new);
    final box = Box.internal(
      name: name,
      api: _api,
      lazy: lazy,
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
      await box.refreshMetadata();
    } catch (_) {
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

  static Future<bool> boxExists(String name) async {
    _ensureInitialized();
    _validateBoxName(name);
    return _api.boxExists(name);
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
