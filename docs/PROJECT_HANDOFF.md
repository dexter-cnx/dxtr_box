# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 claim is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot — 0.3 Hive CE migration implemented

Main before this PR contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, bounded index-name redb iteration, single-snapshot query execution, deterministic planner selection, explicit native `sortBy`, the query/index benchmark matrix, and point-read diagnosis.

PR #23 adds the explicit Hive CE migration path while preserving the core SDK/dependency contract. The next slice after merge is the 0.3 closure audit.

Current capabilities include:

- `DxtrBox`, `Box`, `BoxEvent` Flutter facade.
- Dart >= 3.4.0 / Flutter >= 3.22.0.
- MessagePack dynamic codec.
- Rust `redb = 2.1.0`, one `{box}.dxtr` file per box.
- Transactional CRUD/bulk CRUD/lifecycle.
- Explicit compact and plaintext-to-encrypted migration.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Process crash/reopen durability coverage.
- Exactly three public native profiles: `minimal`, `encryption`, `full`.
- Checked-in FRB 2.8 bindings with drift CI.
- Android/iOS/macOS/Linux/Windows example build coverage.
- Hive CE benchmark smoke harness.
- Declarative `Box.query(BoxQuery)` with one FRB call per query.
- Persisted named scalar indexes under `full`.
- Planner-backed equality and ordered range candidate narrowing.
- Multi-index candidate intersection for AND groups.
- Deterministic native sorting before pagination.
- Diagnostic query/index and point-read benchmark harnesses.
- Explicit Hive CE 2.19.3 migration validation through a separate fixture package.

## Hive CE migration contract

Core `dxtr_box` has **no runtime dependency on Hive CE**. This is intentional so Hive CE does not raise the core package SDK floor or become a transitive dependency for applications that never used it.

Applications wrap an already-open Hive CE box with:

```text
HiveCeMigrationSource
  name
  isOpen callback
  keys callback
  get callback
```

Then call:

```text
migrateFromHiveCe(source, destinationName: ...)
```

Migration invariants:

- source remains open and unmodified;
- caller opens/decrypts encrypted Hive CE sources using Hive CE itself;
- destination must not already exist;
- String keys are preserved;
- int keys default to `@hive-int:<decimal>`;
- custom key/value conversion is explicit;
- converted-key collisions fail before destination creation;
- every converted value is `DxtrCodec`-preflighted before destination creation;
- migrated entries are committed through one `Box.putAll` / one native redb write transaction;
- if `putAll` throws after destination open, the newly-created destination is removed;
- process termination between destination creation and commit can still leave an empty destination and is not claimed crash-atomic.

Real Hive CE 2.19.3 fixtures live under `tool/hive_ce_migration_fixture/` and are isolated from root dependency resolution. Use `make hive-ce-migration-test`.

See `docs/HIVE_CE_MIGRATION_03.md`.

## Query/index public model

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup.and(...)
QueryGroup.or(...)
QueryOperator
QueryLogicalOperator
QuerySort
QuerySortDirection
QueryNullOrder
IndexDefinition
```

Supported predicate semantics:

```text
equal
notEqual
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
isNull
isNotNull
AND / OR groups
dotted nested field lookup
```

Numeric comparison preserves MessagePack integer precision across signed/unsigned domains.

## Persisted index state

```text
index_definitions
index_entries
```

Index lifecycle supports create/backfill/list/drop. Primary mutation and derived index maintenance share the same redb write transaction.

Entry key layout:

```text
[index-name length][index-name]
[scalar length][MessagePack scalar]
[record-key length][record-key]
```

Primary `data` remains authoritative; indexes are derived state.

## Current planner contract

Planner-eligible candidate narrowing includes:

```text
equal
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
```

Eligibility applies at the top level or recursively under `AND` groups when a persisted index exists for the exact dotted field path. The planner does not descend into `OR`; `notEqual`, `isNull`, and `isNotNull` remain scan-backed.

Nested fields such as `profile.age` can be indexed and planned.

For an AND query, usable indexed predicates produce candidate sets which are intersected from smallest to largest. Missing indexes do not fail a query. The full original predicate remains authoritative and is re-evaluated against committed primary data.

## Range lookup correctness constraint

Persisted scalar components are ordinary MessagePack bytes. Their lexicographic byte order is not a general numeric order.

Therefore current range planning does **not** use raw MessagePack bytes as redb numeric range bounds. It bounds iteration by index name, decodes scalar components, and applies the query engine's exact semantic comparator.

A future scalar-level redb range seek requires an order-preserving scalar encoding or equivalent proven ordering contract plus migration/rebuild semantics.

## Query execution path

```text
Box.query(BoxQuery)
  -> DxtrCodec query serialization
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> query::decode_query once
  -> one redb ReadTransaction snapshot
  -> index::candidate_keys(read, filter)
  -> fallback key enumeration when needed
  -> primary record reads from the same snapshot
  -> decrypt if required
  -> full predicate re-evaluation
  -> optional deterministic semantic sort
  -> record-key tie-break
  -> offset / limit
  -> one FRB response
```

Persisted indexes narrow `where` candidates only; they do not claim to satisfy requested ORDER BY.

## Scan/index equivalence gate

`rust/tests/query_index.rs` covers equality, nested ordered ranges, inclusive `between`, multi-index AND intersection, indexed-field mutation correctness, persistence after reopen, deterministic sorting, and encrypted-box scan/index restrictions.

Every future planner rule must add matching scan-vs-index equivalence coverage first.

## Public native profile contract

Keep exactly these three public profiles:

```text
minimal
  CRUD + lifecycle + native watch

encryption
  minimal + encrypted create/open/read/write

full
  encryption + maintenance + query/index implementation
```

Do not add a fourth public query or migration profile.

Reduced profiles reject opening boxes containing persisted index definitions because they cannot safely maintain derived index state.

## Encryption/index security policy

Encrypted boxes may use native scan queries but may not create persisted secondary indexes yet because plaintext-derived scalar keys would leak protected values. Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

## Mutation atomicity invariant

```text
put / putAll / delete / deleteAll / clear
  -> compute index changes
  -> mutate DATA + index_entries
  -> same redb write transaction
  -> one commit
  -> emit watch events after commit only
```

Index creation backfills and persists definition + entries atomically.

## Minimum SDK and native build policy

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

FRB and Cargokit native naming must remain `rust_lib_dxtr_box`. `rust_builder/` remains the native build owner. Dart 3.13 recorded-use/native tree shaking stays deferred.

Hive CE 2.19.3 is intentionally isolated in the migration fixture package so it cannot raise this minimum.

## Benchmark and point-read policy

Shared-runner benchmark timings are diagnostic only. Do not weaken durability or add a Dart whole-box cache merely to improve benchmark numbers.

Query/index diagnostics support the current candidate-narrowing planner but do not justify an order-preserving scalar storage migration yet.

Point-read diagnosis showed Dart decode-only work is small relative to the measured composite native path, but that native region still includes FRB, redb transaction/lookup, native MessagePack validation, optional crypto, and payload copy. No speculative point-read optimization is part of 0.3.

## Developer workflow

Preferred root targets:

```text
make preflight
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make process-crash
make benchmark-smoke
make benchmark-query-index
make diagnose-point-read
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

## Current validation expectation

Before a 0.3 merge, preserve:

```text
Minimum SDK / Flutter 3.22 + Dart 3.4
Current Flutter analyze + tests
FRB generated-binding drift gate
Rust Ubuntu + macOS + Windows
  rustfmt
  clippy -D warnings
  minimal tests
  encryption tests
  full tests
Native Linux FRB round trip
Hive CE 2.19.3 migration fixture analyze + native tests
Native-size same-commit reproducibility
Platform Builds: Android/iOS/macOS/Linux/Windows
```

## Next 0.3 sequence

1. Completed: bounded persisted-index lookup/drop cleanup by index-name range.
2. Completed: one-redb-read-transaction query execution for planner/fallback/primary reads.
3. Completed: deterministic pure planner-selection step with direct selection/fallback tests.
4. Completed: explicit public `sortBy` contract and deterministic native execution.
5. Completed: focused query/index benchmark matrix with machine-readable diagnostic output.
6. Completed: point-get/contains performance diagnosis; retain authoritative native semantics and avoid speculative metadata caching.
7. Completed in PR #23: explicit Hive CE migration path with isolated Hive CE 2.19.3 fixture validation.
8. Next: 0.3 closure audit.
9. Keep encrypted-index design, scalar order-preserving storage encoding, cross-commit size policy, and Dart 3.13 tree shaking outside 0.3 closure unless a release-blocking defect requires otherwise.

## 0.3 closure-audit focus

The next PR should verify, not expand scope:

- README / handoff / walkthrough / query-index / migration docs agree with actual main;
- exactly three public native profiles;
- minimum SDK still passes;
- FRB bindings are current;
- query scan/index/sort equivalence remains green;
- Hive CE migration fixtures remain green;
- no temporary workflows/tools/branches remain;
- all 0.3 roadmap bullets are either completed or explicitly deferred;
- encrypted indexes, true scalar-level range seeks, cross-commit binary-size thresholds, and Dart 3.13 native tree shaking are explicitly deferred.

## Later roadmap

### 0.4.x

- production/package hardening;
- controlled cross-commit native-size policy;
- broader Flutter local-database comparison.

### 0.9.x

Refresh Hive Functional Parity Audit against the then-current Hive CE release and close every practical `Gap`.

### 1.0.0

- no practical parity gaps;
- stable storage/API contract;
- Web/IndexedDB strategy complete;
- pub.dev release readiness.
