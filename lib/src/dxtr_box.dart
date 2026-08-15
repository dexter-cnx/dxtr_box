import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'box.dart';
import 'native_api.dart';

abstract final class DxtrBox {
  static NativeDxtrApi _api = const UnavailableNativeDxtrApi();
  static String? _basePath;

  static bool get isInitialized => _basePath != null;

  /// Package-internal injection point used by generated bindings and tests.
  static void bindNativeApi(NativeDxtrApi api) => _api = api;

  static Future<void> init({String? path}) async {
    final resolvedPath = path ??
        p.join((await getApplicationSupportDirectory()).path, 'dxtr_box');
    await _api.initDb(resolvedPath);
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
    final box = Box.internal(name: name, api: _api, lazy: lazy);
    await box.refreshMetadata();
    return box;
  }

  static Future<void> deleteBox(String name) async {
    _ensureInitialized();
    _validateBoxName(name);
    await _api.deleteBox(name);
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
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name == '.' ||
        name == '..') {
      throw ArgumentError.value(name, 'name', 'Invalid box name');
    }
  }
}
