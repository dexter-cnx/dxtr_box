import 'dart:convert';
import 'dart:io';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:hive_ce/hive.dart' as hive;
import 'package:sembast/sembast.dart' as sembast;
import 'package:sembast/sembast_io.dart' as sembast_io;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite;

typedef ComparisonPayload = Map<String, Object?>;

abstract class LocalDatabaseAdapter {
  String get engine;

  Future<void> open();

  Future<void> close();

  Future<void> destroy();

  Future<void> put(String key, ComparisonPayload value);

  Future<void> putAll(Map<String, ComparisonPayload> values);

  Future<ComparisonPayload?> get(String key);

  Future<bool> containsKey(String key);

  Future<void> deleteAll(List<String> keys);
}

Future<void> initializeComparisonBackends({
  required Directory dxtrRoot,
  required Directory hiveRoot,
}) async {
  await DxtrBox.init(path: dxtrRoot.path);
  hive.Hive.init(hiveRoot.path);
  sqflite.sqfliteFfiInit();
}

List<LocalDatabaseAdapter> createComparisonAdapters({
  required Directory root,
  required String suffix,
}) {
  return <LocalDatabaseAdapter>[
    DxtrComparisonAdapter('comparison_dxtr_$suffix'),
    HiveComparisonAdapter('comparison_hive_$suffix'),
    SembastComparisonAdapter(
      File('${root.path}/sembast_$suffix.db'),
    ),
    SqfliteComparisonAdapter(
      File('${root.path}/sqlite_$suffix.db'),
    ),
  ];
}

class DxtrComparisonAdapter implements LocalDatabaseAdapter {
  DxtrComparisonAdapter(this.name);

  final String name;
  dynamic _box;

  @override
  String get engine => 'dxtr_box';

  @override
  Future<void> open() async {
    _box = await DxtrBox.open(name);
  }

  @override
  Future<void> close() async {
    if (_box != null) {
      await _box.close();
      _box = null;
    }
  }

  @override
  Future<void> destroy() async {
    await close();
    await DxtrBox.deleteBox(name);
  }

  @override
  Future<void> put(String key, ComparisonPayload value) async {
    await _box.put(key, value);
  }

  @override
  Future<void> putAll(Map<String, ComparisonPayload> values) async {
    await _box.putAll(values);
  }

  @override
  Future<ComparisonPayload?> get(String key) async {
    final value = await _box.get(key);
    if (value == null) {
      return null;
    }
    return Map<String, Object?>.from(value as Map);
  }

  @override
  Future<bool> containsKey(String key) => _box.containsKey(key);

  @override
  Future<void> deleteAll(List<String> keys) => _box.deleteAll(keys);
}

class HiveComparisonAdapter implements LocalDatabaseAdapter {
  HiveComparisonAdapter(this.name);

  final String name;
  hive.Box<dynamic>? _box;

  @override
  String get engine => 'hive_ce';

  @override
  Future<void> open() async {
    _box = await hive.Hive.openBox<dynamic>(name);
  }

  @override
  Future<void> close() async {
    await _box?.close();
    _box = null;
  }

  @override
  Future<void> destroy() async {
    await close();
    await hive.Hive.deleteBoxFromDisk(name);
  }

  @override
  Future<void> put(String key, ComparisonPayload value) async {
    await _box!.put(key, value);
  }

  @override
  Future<void> putAll(Map<String, ComparisonPayload> values) async {
    await _box!.putAll(values);
  }

  @override
  Future<ComparisonPayload?> get(String key) async {
    final value = _box!.get(key);
    if (value == null) {
      return null;
    }
    return Map<String, Object?>.from(value as Map);
  }

  @override
  Future<bool> containsKey(String key) async => _box!.containsKey(key);

  @override
  Future<void> deleteAll(List<String> keys) => _box!.deleteAll(keys);
}

class SembastComparisonAdapter implements LocalDatabaseAdapter {
  SembastComparisonAdapter(this.file);

  final File file;
  final sembast.StoreRef<String, Map<String, Object?>> _store =
      sembast.stringMapStoreFactory.store('records');
  sembast.Database? _database;

  @override
  String get engine => 'sembast';

  @override
  Future<void> open() async {
    _database = await sembast_io.databaseFactoryIo.openDatabase(file.path);
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  @override
  Future<void> destroy() async {
    await close();
    await sembast_io.databaseFactoryIo.deleteDatabase(file.path);
  }

  @override
  Future<void> put(String key, ComparisonPayload value) async {
    await _store.record(key).put(_database!, value);
  }

  @override
  Future<void> putAll(Map<String, ComparisonPayload> values) async {
    await _database!.transaction((transaction) async {
      for (final entry in values.entries) {
        await _store.record(entry.key).put(transaction, entry.value);
      }
    });
  }

  @override
  Future<ComparisonPayload?> get(String key) async {
    final value = await _store.record(key).get(_database!);
    return value == null ? null : Map<String, Object?>.from(value);
  }

  @override
  Future<bool> containsKey(String key) async {
    return await _store.record(key).get(_database!) != null;
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    await _database!.transaction((transaction) async {
      for (final key in keys) {
        await _store.record(key).delete(transaction);
      }
    });
  }
}

class SqfliteComparisonAdapter implements LocalDatabaseAdapter {
  SqfliteComparisonAdapter(this.file);

  final File file;
  sqflite.Database? _database;

  @override
  String get engine => 'sqflite_ffi';

  @override
  Future<void> open() async {
    _database = await sqflite.databaseFactoryFfi.openDatabase(
      file.path,
      options: sqflite.OpenDatabaseOptions(
        version: 1,
        onCreate: (database, version) async {
          await database.execute(
            'CREATE TABLE records ('
            'record_key TEXT PRIMARY KEY, '
            'payload TEXT NOT NULL'
            ')',
          );
        },
      ),
    );
  }

  @override
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  @override
  Future<void> destroy() async {
    await close();
    await sqflite.databaseFactoryFfi.deleteDatabase(file.path);
  }

  @override
  Future<void> put(String key, ComparisonPayload value) async {
    await _database!.insert(
      'records',
      <String, Object?>{
        'record_key': key,
        'payload': jsonEncode(value),
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> putAll(Map<String, ComparisonPayload> values) async {
    final batch = _database!.batch();
    for (final entry in values.entries) {
      batch.insert(
        'records',
        <String, Object?>{
          'record_key': entry.key,
          'payload': jsonEncode(entry.value),
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<ComparisonPayload?> get(String key) async {
    final rows = await _database!.query(
      'records',
      columns: <String>['payload'],
      where: 'record_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return Map<String, Object?>.from(
      jsonDecode(rows.single['payload']! as String) as Map,
    );
  }

  @override
  Future<bool> containsKey(String key) async {
    final rows = await _database!.query(
      'records',
      columns: <String>['record_key'],
      where: 'record_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> deleteAll(List<String> keys) async {
    final batch = _database!.batch();
    for (final key in keys) {
      batch.delete(
        'records',
        where: 'record_key = ?',
        whereArgs: <Object?>[key],
      );
    }
    await batch.commit(noResult: true);
  }
}

ComparisonPayload comparisonPayload(int index) => <String, Object?>{
      'id': index,
      'name': 'item-$index',
      'active': index.isEven,
      'score': index / 10,
    };
