# dxtr_box Code Walkthrough

This walkthrough describes the current dxtr_box architecture from the Flutter facade through FRB into Rust/redb, including encryption, native watch fan-out, declarative query execution, persisted secondary indexes, and the first index-backed query planner.

## 1. Package boundary

```text
Flutter app
  -> Dart public API (DxtrBox / Box / query types)
  -> NativeDxtrApi capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

Dart owns public ergonomics, dynamic-value encoding/decoding, lightweight key metadata, lifecycle guards, and public query objects. Rust owns durable storage, transactions, encryption, native watchers, query evaluation, planner/index state, migration, and maintenance.

Values are not retained wholesale in the Dart heap.

## 2. Public lifecycle

`lib/dxtr_box.dart` exports the supported package API. `lib/src/dxtr_box.dart` implements package-level lifecycle:

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');
await box.put('theme', 'dark');
final theme = await box.get('theme');
await box.close();
```

Encrypted boxes use the same open API with `encryptionKey`. Existing plaintext boxes are never silently reinterpreted as encrypted; migration uses explicit `DxtrBox.encryptBox(...)`.

## 3. `Box` state and mutation path

A `Box` keeps lightweight Dart state only:

```text
name
shared key metadata
native watcher id/subscription
closed/closing state
public BoxEvent controller
```

Normal write path:

```text
Box.put
  -> DxtrCodec.encode
  -> FRB
  -> api::put
  -> db::put
  -> validate MessagePack
  -> optional encryption
  -> redb write transaction
  -> persisted-index maintenance when definitions exist
  -> one commit
  -> emit NativeBoxEvent after commit
  -> FRB stream
  -> all registered Box handles
```

`putAll`, `delete`, `deleteAll`, and `clear` preserve the same primary/index atomicity rule: primary data and derived index state commit together.

## 4. Read path

```text
Box.get
  -> NativeDxtrApi.get
  -> FRB
  -> api::get
  -> db::get
  -> redb read transaction
  -> optional AEAD decrypt/authenticate
  -> validate MessagePack
  -> bytes through FRB
  -> DxtrCodec.decode
```

A missing key returns the Dart `defaultValue` when supplied.

## 5. Dynamic codec

`lib/src/codec.dart` uses MessagePack for the Dart/Rust wire/storage value model. Supported values include null, bool, int, double, String, List, `Map<String, dynamic>`, `Uint8List`, and `DateTime`.

Maps use tagged representations so Rust can reconstruct dynamic nested objects without application model code generation.

## 6. Native capability seams and FRB

`lib/src/native_api.dart` defines the main seam and optional capabilities:

```text
NativeDxtrApi
NativeEncryptionMigrationApi
NativeQueryApi
NativeIndexApi
```

`FrbNativeDxtrApi` is the production adapter. Generated Dart bindings live under `lib/src/rust/`; Rust generated bindings live in `rust/src/frb_generated.rs`. CI regenerates with `flutter_rust_bridge_codegen 2.8.0` and fails on drift.

## 7. Declarative query API

Public query types live in `lib/src/query.dart`:

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup
QueryOperator
QueryLogicalOperator
IndexDefinition
```

Example:

```dart
final rows = await box.query(
  BoxQuery(
    where: QueryGroup.and([
      QueryComparison(
        field: 'profile.age',
        operator: QueryOperator.greaterThanOrEqual,
        value: 18,
      ),
      QueryComparison(
        field: 'status',
        operator: QueryOperator.equal,
        value: 'active',
      ),
    ]),
    limit: 20,
  ),
);
```

The public invariant is **one FRB call per query**.

Legacy `Box.where(predicate)` remains a Dart-side linear scan and is separate from the declarative native engine.

## 8. Query decode and predicate engine

`rust/src/query.rs` decodes the tagged MessagePack AST once into `QuerySpec`/`Filter`.

Supported semantics:

- dotted nested-field lookup;
- equal / notEqual;
- greater/less comparisons;
- `between`;
- `isNull` / `isNotNull`;
- AND/OR groups;
- deterministic record-key ordering before pagination.

Numeric comparison preserves MessagePack integer precision. Signed and unsigned integers remain exact rather than being converted wholesale to `f64`; mixed integer/float comparisons use explicit boundary logic.

## 9. First planner stage

The planner is deliberately conservative and internal to Rust. It does not change the Dart or FRB API.

`query::equality_index_candidates(...)` extracts safe scalar equality predicates only from:

```text
QueryComparison(equal)
QueryGroup.and(...)
```

An equality predicate that exists only under `OR` is not considered safe narrowing in this slice.

`rust/src/index.rs` then checks persisted definitions for an index whose field exactly matches an eligible predicate.

```text
query filter
  -> equality_index_candidates
  -> persisted index definitions
  -> first exact field match
  -> encoded equality prefix
  -> candidate record keys from index_entries
```

If no safe persisted index exists, execution falls back to primary-key scan.

## 10. Index-backed query execution

`rust/src/api.rs::scan_query` remains the single FRB query entry point.

Current execution:

```text
Box.query
  -> DxtrCodec query payload
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> api::scan_query
  -> query::decode_query once
  -> index::candidate_keys(filter)
       -> Some(keys) when equality planner is eligible
       -> None when scan is required
  -> sort + deduplicate candidate keys
  -> db::get current primary payload for each candidate
  -> decrypt if encrypted
  -> query::matches_record evaluates complete original predicate
  -> offset / limit
  -> one FRB response with key + payload records
  -> Dart decodes result values
```

The planner **never treats index membership as the final predicate result**. It only narrows candidates. Complete predicate evaluation remains authoritative.

This is important for compound AND filters such as `status == active AND profile.age >= 18`: the status index narrows candidates, then age is still evaluated from primary data.

## 11. Persisted secondary-index storage

`rust/src/index.rs` uses two full-profile redb tables:

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

This avoids delimiter ambiguity.

Equality lookup reconstructs the index-name + scalar prefix, reads matching derived entries, and decodes record keys. The current correctness-first implementation filters the index table by encoded prefix; a more direct redb range implementation can follow without changing semantics.

## 12. Index create/backfill and maintenance

Dart facade:

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-status', field: 'status'),
);
final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-status');
```

Creation path:

```text
Box.createIndex
  -> NativeIndexApi.createIndex
  -> api::create_index
  -> index::create
  -> validate definition
  -> reject encrypted box
  -> scan current DATA
  -> derive scalar entries
  -> one redb write transaction:
       definition + entries
  -> commit
```

Mutation maintenance occurs in the same primary write transaction:

```text
put / putAll
  -> remove old derived entry
  -> add new derived entry
  -> update DATA
  -> one commit

delete / deleteAll
  -> remove derived entry
  -> remove DATA
  -> one commit

clear
  -> clear DATA
  -> clear index entries
  -> one commit
```

Primary `data` remains authoritative.

## 13. Scan/index equivalence tests

`rust/tests/query_index.rs` now verifies both execution modes using the same logical query:

```text
insert records
-> run query before index exists      # scan path
-> create index on status
-> run exact same query                # planner/index candidate path
-> compare ordered keys and payloads
-> mutate indexed status field
-> run query again
-> verify result changes correctly
```

Any future planner eligibility expansion must add equivalent scan-vs-index coverage before it is considered complete.

## 14. Encryption policy

Persisted index creation is rejected for encrypted boxes because plaintext-derived scalar keys would leak protected values.

Encrypted boxes continue to use native scan query. Plaintext -> encrypted migration is rejected while persisted index definitions exist.

Reduced `minimal`/`encryption` builds reject opening boxes that contain persisted index definitions. Those builds do not include index maintenance, so explicit rejection prevents stale derived state.

## 15. Native watch/event ordering

```text
Dart mutation
  -> FRB
  -> redb write transaction
  -> primary + index changes
  -> commit succeeds
  -> Rust emits NativeBoxEvent
  -> FRB stream
  -> Box handles
```

Failed writes do not emit successful events.

## 16. Storage and encryption

Each box is one file:

```text
{base_path}/{box_name}.dxtr
```

Core tables:

```text
data
meta
```

Encryption metadata records format, encryption mode, salt, and encrypted key-check sentinel. Argon2 derives the key; ChaCha20Poly1305 encrypts values with record-key AAD.

## 17. Maintenance, crash durability, and benchmarks

`Box.compact()` is explicit maintenance. Plaintext -> encrypted migration is explicit and transactional.

`rust/tests/process_crash.rs` verifies acknowledged commits survive abrupt process termination and reopen.

The separate `benchmark/` package compares equal logical workloads with Hive CE. Shared-runner timings are informational; CI validates the harness rather than enforcing absolute performance thresholds.

## 18. Native profiles

Exactly three public native profiles remain:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

`full` is the default production build. Do not add a fourth public query profile.

## 19. Developer entry points

Preferred root Make targets:

```text
make preflight
make frb-generate
make native-test
make query-index-test
make process-crash
make benchmark-smoke
make benchmark-full
make rust-check
make native-build-minimal
make native-build-encryption
make native-size-baseline
make native-size-stability
make example-android
make example-linux
make example-windows
make example-macos
make example-ios
```

## 20. Next architectural work

The first equality planner path is now implemented. Next query/index work should remain equivalence-driven:

1. measure whether intersecting multiple indexed AND candidates is worthwhile;
2. add safe range planner eligibility only with exact scan/index equivalence tests;
3. consider redb range-based index lookup optimization;
4. consider one-read-transaction native scan execution;
5. add explicit sort contract / `sortBy` separately;
6. keep encrypted persisted-index design, cross-commit size policy, and Dart 3.13 tree shaking as separate workstreams.
