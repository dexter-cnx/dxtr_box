# dxtr_box Code Walkthrough

This walkthrough describes the current dxtr_box architecture from the Flutter facade through flutter_rust_bridge into Rust/redb, including encryption, native watch fan-out, declarative query execution, persisted secondary indexes, deterministic sorting, diagnostic benchmarks, and Hive CE migration.

## 1. Package boundary

```text
Flutter app
  -> Dart public API (DxtrBox / Box / query + migration types)
  -> NativeDxtrApi capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

Dart owns public ergonomics, dynamic-value encoding/decoding, lightweight key metadata, lifecycle guards, query objects, and Hive CE migration preflight. Rust owns durable storage, transactions, encryption, native watchers, query evaluation, planner/index state, plaintext-to-encrypted migration, and maintenance. Values are not retained wholesale in the Dart heap.

## 2. Public lifecycle and storage

Each box maps to one native file:

```text
{base_path}/{box_name}.dxtr
```

Core redb tables are `data` and `meta`. The `full` profile additionally maintains `index_definitions` and `index_entries`.

Typical Dart lifecycle:

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');
await box.put('theme', 'dark');
final theme = await box.get('theme');
await box.close();
```

Encrypted boxes use the same open API with `encryptionKey`. Plaintext-to-encrypted conversion is explicit through `DxtrBox.encryptBox(...)`.

## 3. Mutation path and index atomicity

```text
Box.put
  -> DxtrCodec.encode
  -> FRB
  -> api::put
  -> db::put
  -> validate MessagePack
  -> optional encryption
  -> redb write transaction
  -> persisted-index maintenance
  -> one commit
  -> NativeBoxEvent after commit
```

`putAll`, `delete`, `deleteAll`, and `clear` preserve the same invariant: primary data and derived index state change in the same redb write transaction. Failed writes do not emit successful watch events.

## 4. Read path

```text
Box.get
  -> NativeDxtrApi.get
  -> FRB
  -> api::get
  -> db::get
  -> redb read transaction
  -> optional AEAD decrypt/authenticate
  -> native MessagePack validation
  -> bytes through FRB
  -> DxtrCodec.decode
```

## 5. Dynamic codec and FRB

`lib/src/codec.dart` uses MessagePack for null, bool, int, double, String, List, `Map<String, dynamic>`, `Uint8List`, and `DateTime`. Tagged forms preserve Dart types that raw MessagePack does not model directly.

`lib/src/native_api.dart` exposes capability seams such as `NativeDxtrApi`, `NativeEncryptionMigrationApi`, `NativeQueryApi`, and `NativeIndexApi`. `FrbNativeDxtrApi` is the production adapter. Checked-in FRB 2.8 bindings are regenerated in CI and drift is rejected.

## 6. Declarative query API

Public query types live in `lib/src/query.dart`:

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup
QueryOperator
QueryLogicalOperator
QuerySort
QuerySortDirection
QueryNullOrder
IndexDefinition
```

The public query invariant is one FRB call per `Box.query(...)`. Legacy `Box.where(predicate)` remains a Dart-side linear scan.

## 7. Query decode and predicate engine

`rust/src/query.rs` decodes the tagged MessagePack AST once into `QuerySpec` and `Filter`.

Supported semantics include dotted nested-field lookup, equality/inequality, ordered comparisons, inclusive `between`, null checks, AND/OR groups, and deterministic ordering. Numeric comparison preserves signed/unsigned integer precision instead of collapsing all integers through `f64`.

## 8. Planner candidate extraction

`query::index_candidates(...)` extracts planner-eligible comparisons from the top level and recursively beneath `AND`. It does not descend into `OR` because narrowing only some OR branches could drop valid rows.

Eligible operators are:

```text
equal
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
```

`notEqual`, `isNull`, and `isNotNull` remain scan-backed. Exact dotted-field matching is required for a persisted index to participate.

Planner selection is a separate deterministic step. If several persisted indexes target the same field, the lexicographically smallest index name wins. Missing definitions simply reduce narrowing opportunities; the full predicate is always authoritative.

## 9. Persisted index representation

`rust/src/index.rs` stores:

```text
index_definitions: index name -> dotted field path
index_entries: encoded composite entry -> empty payload
```

Entry key layout is length-prefixed:

```text
[index-name length][index-name]
[scalar length][MessagePack scalar]
[record-key length][record-key]
```

Primary `data` remains authoritative. Indexes are derived state only.

## 10. Equality and range candidate matching

Persisted scalar bytes are ordinary MessagePack encodings. Their lexicographic byte order is **not** a general numeric order, so current range execution does not use raw MessagePack scalar bytes as redb numeric range bounds.

Instead:

```text
matching index definition
  -> redb half-open range for that index name only
  -> decode stored scalar component
  -> semantic query comparator
  -> collect matching record keys
```

A future scalar-level redb range seek requires a versioned order-preserving scalar encoding plus rebuild/migration semantics.

## 11. Multiple indexed predicates under AND

For an AND query, every usable indexed predicate produces a candidate key set. Sets are sorted by cardinality and intersected from smallest to largest before primary-record recheck.

Missing indexes do not fail the query; usable indexes may still narrow candidates.

## 12. Single-snapshot query execution

`rust/src/api.rs::scan_query` remains the single native query entry point:

```text
Box.query
  -> DxtrCodec query payload
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> query::decode_query once
  -> one redb ReadTransaction snapshot
  -> index::candidate_keys(read, filter)
  -> fallback key enumeration if needed
  -> primary reads from the same snapshot
  -> optional decrypt
  -> full predicate re-evaluation
  -> optional semantic sort
  -> record-key tie-break
  -> offset / limit
  -> one FRB response
```

Persisted index membership is never final truth. Every candidate is re-read from primary data and evaluated against the complete filter.

## 13. Scan/index equivalence gate

`rust/tests/query_index.rs` compares the same query before and after index creation and requires exact result equivalence. Coverage includes equality, nested ordered ranges, `between`, multi-index AND intersection, indexed-field mutation, index persistence, encrypted scan/index restrictions, and deterministic sorting.

Every future planner rule must add matching scan-vs-index equivalence coverage first.

## 14. Index lifecycle and maintenance

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-age', field: 'profile.age'),
);
final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-age');
```

Creation validates, rejects encrypted boxes, backfills, and commits the definition plus derived entries atomically. Primary mutations maintain old/new index entries in the same write transaction as primary data.

## 15. Encryption and reduced-profile safety

Encrypted boxes may use native scan queries but may not create persisted indexes yet because plaintext-derived scalar keys would leak protected values. Plaintext-to-encrypted migration is rejected while indexes exist.

`minimal` and `encryption` builds reject opening boxes containing persisted indexes because those profiles cannot safely maintain derived state.

## 16. Native watch ordering

```text
Dart mutation
  -> FRB
  -> redb write transaction
  -> primary + index changes
  -> commit
  -> Rust NativeBoxEvent
  -> FRB stream
  -> Box handles
```

## 17. Public native profiles

Exactly three public native profiles remain:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

`full` is the default production build. Query/index and migration work do not add a fourth profile.

## 18. Bounded persisted-index iteration

Candidate lookup and `dropIndex` cleanup bound redb iteration to the selected encoded index-name prefix using a half-open range. This optimization is intentionally limited to the index-name component; scalar MessagePack values are still decoded and compared semantically.

## 19. Deterministic native query sorting

`BoxQuery.sortBy` carries ordered `QuerySort` clauses inside the existing MessagePack query payload, so FRB shape does not change.

Sorted execution collects predicate matches from the same redb snapshot, validates each sort field's ordered domain, applies clauses in order, uses explicit null/missing placement, and finally uses record key ascending as a deterministic tie-break. Pagination happens **after** sorting.

Numeric sort reuses exact signed/unsigned/float semantics. Mixed numeric/string values for one sort field and NaN are rejected. Explicit null placement is not reversed when direction is descending. Persisted indexes narrow `where`; they do not satisfy ORDER BY.

## 20. Query/index diagnostic benchmark

`benchmark/test/query_index_benchmark_test.dart` compares scan and indexed execution for equality, range, AND-intersection, and sorted-range workloads. Setup/backfill are excluded from timed regions.

The 2026-08-16 diagnostic baseline showed lower median query time for indexed execution in every measured case, but timings are informational only. The result supports current candidate narrowing; it does not justify a persisted scalar encoding migration yet.

## 21. Point-read diagnosis

The point-read harness measures production paths without adding a benchmark-only public API:

```text
Box.get
  -> Dart wrapper
  -> NativeDxtrApi.get
  -> FRB
  -> redb point read transaction
  -> optional decrypt/authenticate
  -> native MessagePack validation
  -> FRB payload copy
  -> DxtrCodec.decode
```

The shared-runner baseline measured Dart decode-only work far below the composite native path, but the native region still includes FRB, redb, native MessagePack validation, optional crypto, and copy costs. Therefore 0.3 keeps authoritative native `get` / `containsKey` semantics and avoids speculative Dart caching.

## 22. Hive CE migration path

`lib/src/hive_ce_migration.dart` adds migration without taking a runtime Hive CE dependency.

Applications open their Hive CE source normally, including any Hive CE cipher or TypeAdapters, then wrap it:

```dart
final source = HiveCeMigrationSource(
  name: hiveBox.name,
  isOpen: () => hiveBox.isOpen,
  keys: () => hiveBox.keys,
  get: hiveBox.get,
);
```

Execution path:

```text
migrateFromHiveCe
  -> require DxtrBox.init
  -> require source still open
  -> reject existing destination
  -> enumerate source keys
  -> keyConverter or default String/int mapping
  -> detect converted-key collisions
  -> normalize supported values recursively
  -> valueConverter for unsupported/custom values
  -> DxtrCodec.encode preflight for every entry
  -> DxtrBox.open(new destination)
  -> one Box.putAll(prepared)
       -> one native putAll write transaction
  -> close destination
  -> HiveCeMigrationResult
```

Default int keys become `@hive-int:<decimal>`. Source String keys are preserved, so a String key equal to a converted int key is detected as a collision.

The source is read-only from dxtr_box's perspective. Encrypted Hive CE sources are decrypted by Hive CE before callbacks return values. `destinationEncryptionKey` uses the normal dxtr_box encrypted-open path.

If preflight fails, destination creation never begins. If `putAll` throws after a successful destination open, migration closes and deletes the newly-created destination. A hard process kill between destination creation and commit can still leave an empty destination; 0.3 does not claim file-level crash-atomic promotion.

## 23. Hive CE fixture isolation

Hive CE 2.19.3 requires dependencies that would raise the root package's effective minimum on Flutter 3.22. To preserve the public SDK contract, real Hive CE fixtures live in a separate package:

```text
tool/hive_ce_migration_fixture/
  pubspec.yaml -> hive_ce 2.19.3 + path dependency on dxtr_box
  test/        -> real Hive CE source boxes
```

Root analyzer excludes that fixture package; CI performs a separate `flutter pub get`, `flutter analyze`, and native test run inside it.

Fixture coverage includes primitives, lists/maps, bytes, DateTime, String/int keys, BigInt conversion, collision rejection, unsupported-value preflight failure, existing-destination rejection, encrypted Hive CE source, encrypted dxtr_box destination, and source preservation.

Run:

```text
make hive-ce-migration-test
```

## 24. Current 0.3 boundary

The next work is a **closure audit**, not another feature slice. Keep these outside 0.3 closure unless needed to fix a release blocker:

- encrypted persisted indexes;
- order-preserving persisted scalar encoding / true scalar-level redb range seeks;
- cross-commit native-size regression thresholds;
- Dart 3.13 recorded-use/native tree shaking.

Important developer targets now include:

```text
make preflight
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make benchmark-query-index
make diagnose-point-read
make rust-check
make native-size-stability
make example-android
make example-ios
make example-macos
make example-linux
make example-windows
```
