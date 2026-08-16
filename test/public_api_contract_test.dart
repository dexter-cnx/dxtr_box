import 'dart:async';

import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/verify_public_storage_contract.dart' as contract;

void main() {
  test('public export and durable storage identities remain explicit', () {
    contract.verifyPublicStorageContract();
  });

  test('public value and query types remain constructible', () {
    const event = BoxEvent(
      boxName: 'settings',
      type: BoxEventType.put,
      key: 'theme',
      value: 'dark',
    );
    expect(event.boxName, 'settings');

    final comparison = QueryComparison(
      field: 'profile.age',
      operator: QueryOperator.greaterThanOrEqual,
      value: 18,
    );
    final query = BoxQuery(
      where: QueryGroup.and(<QueryFilter>[comparison]),
      sortBy: <QuerySort>[
        QuerySort(
          field: 'profile.age',
          direction: QuerySortDirection.descending,
          nulls: QueryNullOrder.last,
        ),
      ],
      limit: 20,
      offset: 0,
    );
    expect(query.where, isA<QueryGroup>());

    final index = IndexDefinition(name: 'by-age', field: 'profile.age');
    expect(index.name, 'by-age');

    const source = HiveCeMigrationSource(
      name: 'legacy',
      isOpen: _true,
      keys: _emptyKeys,
      get: _nullValue,
    );
    expect(source.isOpen, isTrue);

    const result = HiveCeMigrationResult(
      sourceName: 'legacy',
      destinationName: 'settings',
      entriesMigrated: 0,
    );
    expect(result.entriesMigrated, 0);

    const HiveCeValueConverter valueConverter = _identity;
    const HiveCeKeyConverter keyConverter = _stringKey;
    expect(valueConverter('value'), 'value');
    expect(keyConverter(1), '1');

    expect(DxtrBox.isInitialized, isA<bool>());
  });
}

// These helpers are intentionally not executed. Their typed tear-offs are
// compile-time contracts for the consumer-facing methods and named parameters.
void assertBoxSurface(Box box) {
  final String name = box.name;
  final int length = box.length;
  final bool isEmpty = box.isEmpty;
  final Iterable<String> keys = box.keys;
  final Future<List<dynamic>> values = box.values;

  final Future<void> Function(String, dynamic) put = box.put;
  final Future<void> Function(Map<String, dynamic>) putAll = box.putAll;
  final Future<dynamic> Function(String, {dynamic defaultValue}) get = box.get;
  final Future<bool> Function(String) containsKey = box.containsKey;
  final Future<void> Function(String) delete = box.delete;
  final Future<void> Function(Iterable<String>) deleteAll = box.deleteAll;
  final Future<void> Function() clear = box.clear;
  final Future<bool> Function() compact = box.compact;
  final Future<List<MapEntry<String, dynamic>>> Function(BoxQuery) query =
      box.query;
  final Future<void> Function(IndexDefinition) createIndex = box.createIndex;
  final Future<List<IndexDefinition>> Function() listIndexes = box.listIndexes;
  final Future<bool> Function(String) dropIndex = box.dropIndex;
  final Future<void> Function() close = box.close;
  final Future<List<MapEntry<String, dynamic>>> Function(
    bool Function(dynamic),
  ) where = box.where;
  final Stream<BoxEvent> Function({String? key}) watch = box.watch;

  Object.hash(
    name,
    length,
    isEmpty,
    keys,
    values,
    put,
    putAll,
    get,
    containsKey,
    delete,
    deleteAll,
    clear,
    compact,
    query,
    createIndex,
    listIndexes,
    dropIndex,
    close,
    where,
    watch,
  );
}

void assertDxtrBoxSurface() {
  final bool isInitialized = DxtrBox.isInitialized;
  const Future<void> Function({String? path}) init = DxtrBox.init;
  const Future<Box> Function(
    String, {
    String? encryptionKey,
    bool lazy,
  }) open = DxtrBox.open;
  const Future<void> Function(String) deleteBox = DxtrBox.deleteBox;
  const Future<void> Function(
    String, {
    required String encryptionKey,
  }) encryptBox = DxtrBox.encryptBox;
  const Future<bool> Function(String) boxExists = DxtrBox.boxExists;

  Object.hash(
    isInitialized,
    init,
    open,
    deleteBox,
    encryptBox,
    boxExists,
  );
}

void assertHiveCeMigrationSurface() {
  const Future<HiveCeMigrationResult> Function(
    HiveCeMigrationSource, {
    required String destinationName,
    String? destinationEncryptionKey,
    HiveCeValueConverter? valueConverter,
    HiveCeKeyConverter? keyConverter,
  }) migrate = migrateFromHiveCe;

  Object.hash(migrate, migrate);
}

bool _true() => true;
Iterable<dynamic> _emptyKeys() => const <dynamic>[];
dynamic _nullValue(dynamic _) => null;
dynamic _identity(dynamic value) => value;
String _stringKey(dynamic key) => '$key';
