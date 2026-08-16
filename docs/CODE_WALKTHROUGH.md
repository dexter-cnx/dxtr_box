# dxtr_box Code Walkthrough

This walkthrough describes the current dxtr_box architecture from the Flutter facade through flutter_rust_bridge into Rust/redb, including encryption, native watch fan-out, declarative query execution, persisted secondary indexes, and the current range-capable index planner.

## 1. Package boundary

```text
Flutter app
  -> Dart public API (DxtrBox / Box / query types)
  -> NativeDxtrApi capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

Dart owns public ergonomics, dynamic-value encoding/decoding, lightweight key metadata, lifecycle guards, and public query objects. Rust owns durable storage, transactions, encryption, native watchers, query evaluation, planner/index state, migration, and maintenance. Values are not retained wholesale in the Dart heap.

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

Encrypted boxes use the same open API with `encryptionKey`. Plaintext to encrypted conversion is explicit through `DxtrBox.encryptBox(...)`.

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
  -> validate MessagePack
  -> bytes through FRB
  -> DxtrCodec.decode
```

## 5. Dynamic codec and FRB

`lib/src/codec.dart` uses MessagePack for null, bool, int, double, String, List, `Map<String, dynamic>`, `Uint8List`, and `DateTime`. Tagged map/list forms let Rust reconstruct nested dynamic objects without generated application models.

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

The public query invariant remains one FRB call per `Box.query(...)`. Legacy `Box.where(predicate)` remains a Dart-side linear scan.

## 7. Query decode and predicate engine

`rust/src/query.rs` decodes the tagged MessagePack AST once into `QuerySpec` and `Filter`.

Supported semantics:

- dotted nested-field lookup;
- `equal`, `notEqual`;
- `greaterThan`, `greaterThanOrEqual`;
- `lessThan`, `lessThanOrEqual`;
- `between`;
- `isNull`, `isNotNull`;
- AND/OR groups;
- deterministic record-key ordering before offset/limit.

Numeric comparison preserves MessagePack integer precision across signed and unsigned domains instead of collapsing all integers through `f64`.

## 8. Planner candidate extraction

The planner is internal to Rust and does not change the Dart or FRB surface.

`query::index_candidates(...)` extracts index-eligible comparisons from the top level and recursively from `AND` groups. It never descends into `OR` for narrowing because intersecting a subset of OR branches could drop valid results.

Eligible operators are:

```text
equal
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
```

Ordered range candidates require numeric or string scalar bounds. `notEqual`, `isNull`, and `isNotNull` remain scan-backed.

Nested dotted fields such as `profile.age` are eligible when a persisted index exists for that exact field path.

Planner selection is a separate pure internal step in `rust/src/index.rs`. Candidate extraction determines what predicates are safe to index; selection matches those candidates to persisted definitions by exact field path. If several persisted indexes target the same field, the lexicographically smallest index name is chosen deterministically. Missing definitions are ignored, so an `AND` group may still narrow through the usable subset. An empty selection means native scan fallback. Unit coverage locks these choices independently from storage lookup.

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

Equality and range planning use the same logical comparison semantics as the primary predicate engine.

A critical storage detail is that persisted scalar bytes are ordinary MessagePack encodings. Their lexicographic byte order is **not** a general numeric sort order. Therefore the current implementation does not use raw MessagePack byte ordering as a redb numeric range bound.

Instead, for a matching index definition:

```text
index::lookup_candidate
  -> iterate entries belonging to that index name
  -> decode the stored scalar component
  -> query::index_candidate_matches(...)
       -> exact equality/range comparison using query comparator
  -> decode matching record keys
```

This is intentionally correctness-first. A future efficient redb range seek requires an order-preserving scalar encoding or equivalent representation whose ordering contract is proven to match query semantics.

## 11. Multiple indexed predicates under AND

When an `AND` group contains multiple planner-eligible predicates and matching persisted indexes exist, `index::candidate_keys(...)` builds a record-key set for each usable index.

```text
AND filter
  -> candidate A -> index set A
  -> candidate B -> index set B
  -> ...
  -> sort sets by size
  -> intersect from smallest set
  -> candidate record keys
```

Using the smallest set first reduces intersection work. Missing indexes do not make the query fail; they simply contribute no narrowing set and the remaining usable indexes may still narrow candidates.

## 12. Index-backed query execution

`rust/src/api.rs::scan_query` remains the single native query entry point.

```text
Box.query
  -> DxtrCodec query payload
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> api::scan_query
  -> query::decode_query once
  -> open one redb ReadTransaction snapshot
  -> index::candidate_keys(read, filter)
       -> index definitions + entry ranges from the same snapshot
       -> Some(keys) for usable equality/range index candidates
       -> None when scan is required
  -> fallback key enumeration from the same snapshot when needed
  -> sort + deduplicate candidate keys
  -> primary payload reads from the same snapshot
  -> decrypt if required
  -> query::matches_record evaluates complete original predicate
  -> deterministic key ordering
  -> offset / limit
  -> one FRB response
```

The planner never treats persisted index membership as final truth. Every candidate is re-read from committed primary data and re-evaluated with the complete original predicate. Candidate discovery and primary-record reads now share one redb read transaction, so a single query observes one consistent redb snapshot instead of composing several independently opened read snapshots.

## 13. Scan/index equivalence gate

`rust/tests/query_index.rs` proves planner expansion against the authoritative scan path.

Coverage now includes:

```text
same query before index creation -> scan
same query after index creation  -> planner/index path
compare ordered results exactly
```

The suite covers nested `profile.age` indexes for `>`, `>=`, `<`, `<=`, and inclusive `between`, plus an AND query where `status == active` and `profile.age >= 18` are both indexed and their candidate sets are intersected.

Existing coverage also verifies transactional indexed-field mutation, index persistence after reopen, encrypted-box scan fallback, and rejection of encrypted persisted-index creation.

Every future planner rule must add scan-vs-index equivalence coverage before it is considered complete.

## 14. Index lifecycle and maintenance

Dart facade:

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-age', field: 'profile.age'),
);
final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-age');
```

Creation validates the definition, rejects encrypted boxes, backfills from current `data`, and commits the definition plus derived entries atomically.

For primary mutations, old index entries are removed and new entries inserted in the same transaction as the primary change.

## 15. Encryption and reduced-profile safety

Encrypted boxes may use native scan query but may not create persisted secondary indexes yet, because plaintext-derived scalar index keys would leak protected values. Plaintext-to-encrypted migration is rejected while persisted indexes exist.

`minimal` and `encryption` builds reject opening boxes that already contain persisted index definitions because those profiles cannot maintain derived index state safely.

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

## 17. Profiles and validation

Exactly three public native profiles remain:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

`full` is the default production build. Query/index work does not add a fourth profile.

Important developer targets include:

```text
make preflight
make frb-generate
make native-test
make query-index-test
make rust-check
make benchmark-smoke
make native-size-stability
make example-android
make example-ios
make example-macos
make example-linux
make example-windows
```

## 18. Next architectural work

The range-capable planner is now implemented with equivalence coverage. Next work should stay correctness-driven:

1. keep bounded index-name ranges, deterministic planner selection, and the single-read-transaction query snapshot as execution invariants;
2. preserve deterministic `sortBy` semantics and scan/index equivalence as query execution invariants;
3. add focused query/index benchmark scenarios now that planner selection and execution semantics are stable;
4. define an order-preserving scalar encoding only if scalar-level redb range seek is justified by benchmarks;
6. keep encrypted persisted-index design, cross-commit native-size policy, and Dart 3.13 tree shaking as separate workstreams.

## 19. Bounded persisted-index iteration

Persisted-index candidate lookup no longer iterates the entire `index_entries` table. `rust/src/index.rs` computes the encoded index-name prefix and its lexicographic successor, then asks redb for only that half-open key range. `dropIndex` cleanup uses the same bounded range.

This optimization is deliberately limited to the **index-name component**. Scalar MessagePack bytes inside that range are still decoded and compared with the query engine comparator, so numeric/string query semantics are unchanged and raw MessagePack byte ordering is never treated as numeric ordering.

A future scalar-level redb range seek still requires a proven order-preserving scalar encoding.


## 20. Deterministic native query sorting

`BoxQuery` now accepts an ordered `sortBy` list. Public sort clauses are represented by `QuerySort`, `QuerySortDirection`, and `QueryNullOrder`; they are serialized inside the existing opaque MessagePack query payload, so the FRB function shape does not change.

Sorted execution deliberately separates filtering/planning from ordering:

```text
Box.query(sortBy: ...)
  -> planner discovers candidate keys as before
  -> one redb read snapshot
  -> primary records are re-read and full predicates re-evaluated
  -> extract ordered sort values from nested dotted fields
  -> validate non-null values for each sort field use one compatible ordered domain
  -> stable semantic comparison across sort clauses
  -> record key is the final deterministic tie-break
  -> offset / limit are applied after sorting
```

Numeric ordering reuses the exact query comparator and therefore preserves signed/unsigned integer precision, including values above 2^53. String ordering is lexical. Missing fields and explicit null values form one nullish category whose placement is controlled independently with `QueryNullOrder.first` or `.last`; sort direction does not invert explicit null placement.

A sort field rejects unsupported non-null values, NaN, and mixtures of numeric and string values in the same ordered column. This makes ordering behavior explicit instead of relying on an implicit cross-type total order.

The unsorted path keeps its existing deterministic record-key order and early pagination behavior. The sorted path must collect all predicate matches visible in the same redb snapshot before applying ordering and pagination.

`rust/tests/query_index.rs` verifies order-before-pagination, nested sort fields, null/missing placement, mixed-type rejection, large-integer precision, deterministic key tie-breaking, and exact scan/index result equivalence. `make query-sort-test` runs the focused Dart contract and Rust integration coverage.
