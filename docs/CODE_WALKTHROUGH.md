# dxtr_box Code Walkthrough

This walkthrough describes the current dxtr_box architecture from the Flutter facade through flutter_rust_bridge into Rust/redb, plus the production-hardening gates around native profile size.

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

Typical lifecycle:

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

Point reads remain authoritative and native-backed. 0.3 diagnosis did not justify a Dart whole-box cache.

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

`rust/src/query.rs` decodes the tagged MessagePack AST once into the native query representation.

Supported semantics include dotted nested-field lookup, equality/inequality, ordered comparisons, inclusive `between`, null checks, AND/OR groups, and deterministic ordering. Numeric comparison preserves signed/unsigned integer precision instead of collapsing all integers through `f64`.

## 8. Planner candidate extraction

Planner-eligible comparisons are extracted from the top level and recursively beneath `AND`. The planner does not descend into `OR` because narrowing only some OR branches could drop valid rows.

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

Planner selection is deterministic. Missing definitions simply reduce narrowing opportunities; the full predicate remains authoritative.

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

Persisted scalar bytes are ordinary MessagePack encodings. Their lexicographic byte order is not a general numeric order, so current range execution does not use raw scalar bytes as redb numeric range bounds.

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

For an AND query, every usable indexed predicate produces a candidate key set. Sets are intersected from smallest to largest before primary-record recheck.

Missing indexes do not fail the query; usable indexes may still narrow candidates.

## 12. Single-snapshot query execution

`rust/src/api.rs::scan_query` is the single native query entry point:

```text
Box.query
  -> DxtrCodec query payload
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> decode query once
  -> one redb ReadTransaction snapshot
  -> index candidate narrowing or fallback enumeration
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

`full` is the default production build. Production hardening must not add a fourth public profile merely to influence binary size.

## 18. Bounded persisted-index iteration

Candidate lookup and `dropIndex` cleanup bound redb iteration to the selected encoded index-name prefix using a half-open range. This optimization is intentionally limited to the index-name component; scalar MessagePack values are still decoded and compared semantically.

## 19. Deterministic native query sorting

`BoxQuery.sortBy` carries ordered `QuerySort` clauses inside the existing MessagePack query payload, so FRB shape does not change.

Sorted execution collects predicate matches from the same redb snapshot, validates each sort field's ordered domain, applies clauses in order, uses explicit null/missing placement, and finally uses record key ascending as a deterministic tie-break. Pagination happens after sorting.

Persisted indexes narrow `where`; they do not satisfy ORDER BY.

## 20. Query/index diagnostic benchmark

`benchmark/test/query_index_benchmark_test.dart` compares scan and indexed execution for equality, range, AND-intersection, and sorted-range workloads. Setup/backfill are excluded from timed regions.

Shared-runner timings are diagnostic only. Correctness/equivalence remains the hard gate.

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

The native region is composite. 0.3 retained authoritative native `get` / `containsKey` semantics and rejected speculative Dart caching.

## 22. Hive CE migration path

`lib/src/hive_ce_migration.dart` adds migration without taking a runtime Hive CE dependency.

Execution path after the final PR #25 correctness closure:

```text
migrateFromHiveCe
  -> require DxtrBox.init
  -> require source still open
  -> enumerate source keys
  -> key/value conversion + collision checks
  -> DxtrCodec preflight for every entry
  -> acquire exclusive migration reservation marker
  -> re-check destination does not already exist
  -> atomically create {destination}.dxtr exclusively
  -> open destination through migration-only internal path
  -> one Box.putAll(prepared)
       -> one native putAll write transaction
  -> close destination
  -> release reservation marker
  -> HiveCeMigrationResult
```

Ordinary open exclusion is part of the correctness contract:

```text
DxtrBox.open(destinationName)
  -> reject if reservation is already active
  -> native open / handle initialization
  -> re-check reservation
  -> if migration acquired ownership while open was in flight:
       close handle
       reject ordinary open
```

The second check closes the race where an ordinary open starts immediately before migration acquires the reservation.

Initialization/write failures remove migration-owned destination state and release the marker. Successful migration also releases the marker after close.

A hard process kill may still leave an incomplete destination and reservation marker; file-level staging/promotion and automatic stale-reservation recovery are deferred.

## 23. Hive CE fixture isolation

Real Hive CE 2.19.3 fixtures live in `tool/hive_ce_migration_fixture/` so Hive CE cannot raise the root package's Dart 3.4 / Flutter 3.22 minimum.

Coverage includes primitive/list/map/binary/DateTime values, String/int keys, custom conversion, collision rejection, encrypted source/destination, source preservation, concurrent migration exclusion, ordinary-open exclusion, and initialization-failure cleanup.

Run:

```text
make hive-ce-migration-test
```

## 24. Native size measurement foundation from 0.3

Three tools establish the measurement chain:

```text
tool/native_size_baseline.sh
  -> one release build per profile
  -> exact artifact bytes + git/toolchain/platform metadata

tool/native_size_stability.sh
  -> repeated isolated builds of the same commit/profile
  -> min/max/spread
  -> fail if spread != 0
```

PR #12 established profile baselines. PR #13 verified same-commit reproducibility before any cross-commit budget was introduced.

The same-commit check remains a prerequisite in 0.4.

## 25. 0.4 cross-commit native-size regression gate

`tool/native_size_regression.sh` adds the first Production Hardening gate.

Inputs:

```text
DXTR_BOX_SIZE_BASE_REF
DXTR_BOX_SIZE_MAX_GROWTH_BYTES   default 65536
DXTR_BOX_SIZE_MAX_GROWTH_PERCENT default 3
```

The default base is `HEAD^` for local use. CI passes the pull-request base SHA (or prior push SHA) explicitly.

Comparison flow:

```text
current checkout
  -> resolve base SHA + head SHA
  -> create detached Git worktree for base SHA

base SHA
  -> isolated Cargo target dirs
  -> build minimal
  -> build encryption
  -> build full

head SHA
  -> separate isolated Cargo target dirs
  -> build minimal
  -> build encryption
  -> build full

same runner + same OS/arch + same rustc/cargo
  -> exact byte comparison per profile
```

For each profile:

```text
delta = head_bytes - base_bytes
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))

if delta > allowed_growth:
  fail
else:
  pass
```

Shrinks pass. Growth exactly at the allowance passes.

The script writes:

```text
build/native-size-regression/native-size-regression.tsv
```

including base/head SHAs, toolchain/platform metadata, profile bytes, deltas, effective allowance, growth percentage, and status.

Why base/head are built in one job instead of comparing historical artifacts: a historical measurement may have been produced by another runner image or Rust toolchain. Rebuilding both commits in one environment keeps source revision as the controlled comparison variable.

CI's `native-size` job therefore now performs three distinct checks:

```text
absolute current profile measurement
same-commit reproducibility
cross-commit growth budget
```

and uploads all three TSV files.

Local commands:

```text
make native-size-regression
make native-size-regression SIZE_BASE_REF=origin/main
```

The size budget is an alarm, not a target. Intentional growth must be documented with measured deltas and reviewed explicitly rather than bypassed.

See `docs/NATIVE_SIZE_POLICY_04.md`.

## 26. Current milestone state

0.3 query/index + Hive CE migration is closed. 0.4 Production Hardening is active.

Preserve:

- exactly three public native profiles;
- primary data authoritative over derived indexes;
- one read snapshot per native query;
- full predicate re-evaluation after index narrowing;
- exact numeric semantics and deterministic sorting;
- no plaintext-derived persisted indexes for encrypted boxes;
- migration reservation ownership and ordinary-open exclusion;
- Dart >= 3.4 / Flutter >= 3.22 minimum;
- FRB 2.8 generated-binding drift gate;
- size policy must not trade away correctness, durability, encryption, or SDK compatibility.

Important developer targets:

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
make native-size-baseline
make native-size-stability
make native-size-regression
make example-android
make example-ios
make example-macos
make example-linux
make example-windows
```

Next 0.4 slice after the size policy is package-quality / publish-readiness hardening.

Still deferred:

- encrypted persisted indexes;
- order-preserving scalar encoding / scalar-level redb range seeks;
- index-backed ORDER BY;
- Dart 3.13 recorded-use/native tree shaking;
- LazyBox migration and direct `.hive` parsing;
- file-level crash-atomic migration staging/promotion and automatic stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB and remaining 1.0 functional-parity gaps.
