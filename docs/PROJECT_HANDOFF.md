# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 product claim is **functional replacement for practical Hive/Hive CE local-database workloads**, not source-level/drop-in API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate: any practical capability classified as `Gap` blocks the 1.0 claim.

## Current snapshot — 0.3 query/index planner

PR #14 established the executable native query/index foundation. The current branch `feature/0.3-index-query-planner` adds the first persisted-index-backed planner path without changing the public Dart or FRB API.

Current public/native capabilities:

- `DxtrBox`, `Box`, `BoxEvent` Flutter facade.
- Dart >= 3.4.0 / Flutter >= 3.22.0 compatibility floor with dedicated CI.
- MessagePack codec for dynamic Flutter values.
- Rust `redb = 2.1.0`, one `{box}.dxtr` file per box.
- Transactional CRUD/bulk CRUD/lifecycle.
- Explicit `compact()` maintenance.
- Native cross-handle watch fan-out through FRB streams.
- Persisted per-box encryption using Argon2 + ChaCha20Poly1305.
- Explicit transactional plaintext -> encrypted migration.
- Process-level crash/reopen durability coverage for acknowledged commits.
- Exactly three public native profiles: `minimal`, `encryption`, `full`.
- Linux native-size same-commit reproducibility gate.
- Hive CE benchmark smoke harness; timings remain informational.
- Checked-in FRB 2.8 bindings with generated-drift CI.
- Android/iOS/macOS/Linux/Windows example build coverage.
- Root Makefile for normal validation/build workflows.
- Declarative `Box.query(BoxQuery)` with one FRB call per query.
- Persisted named scalar secondary indexes in the `full` profile.
- Conservative persisted-index planner for scalar equality predicates.

## Query/index implementation state

Public query model:

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup.and(...)
QueryGroup.or(...)
QueryOperator
QueryLogicalOperator
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

Numeric comparison preserves MessagePack integer precision across signed/unsigned integers instead of converting all numeric values to `f64`.

Persisted index state:

```text
index_definitions
index_entries
```

Index lifecycle supports create/backfill/list/drop. Primary mutation and derived index maintenance share the same redb write transaction.

## First planner contract

The planner is conservative by design.

Eligible candidate narrowing currently means a scalar `equal` predicate that is either:

```text
- the top-level comparison; or
- contained under an AND group
```

and a persisted index exists for the exact dotted field.

An equality predicate found only under an `OR` group is not used for narrowing. Range operators, `between`, inequality, and null-specific operators also remain scan-backed for now.

Execution path:

```text
Box.query(BoxQuery)
  -> DxtrCodec query serialization
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> Rust query::decode_query once
  -> query::equality_index_candidates
  -> index::candidate_keys
       -> persisted-index candidate keys when safe
       -> otherwise native primary-key scan
  -> sort + deduplicate candidate keys
  -> read current primary records
  -> decrypt if required
  -> evaluate the complete original predicate
  -> deterministic key ordering
  -> offset / limit
  -> one FRB response
  -> Dart decode values
```

Important invariant: the persisted index **only narrows candidates**. Full predicate evaluation against primary committed data remains authoritative.

## Scan/index equivalence gate

`rust/tests/query_index.rs` now exercises the same logical query through both execution modes:

```text
query before index creation
  -> scan path

create matching index
query again
  -> planner/index candidate path

compare ordered keys + payloads
mutate indexed field
query again
  -> verify transactional index maintenance changes results correctly
```

Any future planner eligibility expansion must add matching scan-vs-index equivalence coverage first.

## Public native profile contract

Keep exactly these three public product profiles:

```text
minimal
  CRUD + lifecycle + native watch

encryption
  minimal + encrypted create/open/read/write

full
  encryption + maintenance + query/index implementation
```

`full` remains the default production build used by Flutter/Cargokit.

Do **not** add a fourth public query profile. Internal optional dependencies required by full-profile implementation are allowed; `rmpv` currently belongs to `full`.

Reduced profiles retain a stable FRB-facing symbol surface and fail explicitly for unavailable capabilities.

Additional safety rule: a `minimal` or `encryption` build rejects opening a box that already contains persisted index definitions, because those builds do not maintain derived index state.

## Minimum SDK policy

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

Do not raise this floor incidentally. Dart 3.13 recorded-use/native tree shaking remains future-only and must not become required for correctness.

## Native naming/build invariant

FRB and Cargokit must agree on:

```text
rust_lib_dxtr_box
```

`rust_builder/` is the sole native build owner. Do not reintroduce duplicate root platform FFI scaffolding.

## Storage architecture

One box maps to:

```text
{base_path}/{box_name}.dxtr
```

Core redb tables:

```text
data
meta
```

Full query/index adds:

```text
index_definitions
index_entries
```

Primary `data` is always authoritative. Secondary indexes are derived state.

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

## Persisted index encoding

Current scalar entry key layout is length-aware binary composition:

```text
[index-name length][index-name]
[scalar length][MessagePack scalar]
[record-key length][record-key]
```

No delimiter concatenation is used.

The equality planner reconstructs the index-name + scalar prefix and decodes matching record keys. The current implementation filters index entries by prefix; a more efficient redb range lookup is a later performance improvement and must preserve semantics.

## Encrypted query/index security policy

Encrypted boxes **may use native scan query**.

Encrypted boxes **may not create persisted secondary indexes yet**.

Reason: plaintext-derived scalar index keys would leak values protected by encrypted primary storage.

Plaintext -> encrypted migration is rejected while persisted index definitions exist.

Do not weaken either restriction until a non-leaking encrypted-index representation and migration contract are explicitly designed.

## Encryption architecture

Encrypted boxes persist format/encryption metadata, unique random salt, Argon2-derived key validation, and ChaCha20Poly1305 ciphertext. Record keys are used as AAD. Wrong keys, tampering, and swapped ciphertext are rejected before plaintext reaches Dart.

## Native watch ordering

```text
Dart mutation
  -> FRB
  -> redb write transaction
  -> primary/index changes
  -> commit
  -> Rust NativeBoxEvent
  -> FRB stream
  -> Box handles
```

Failed writes do not emit successful public events.

## Benchmark policy

The separate `benchmark/` package compares equal logical workloads with Hive CE without raising the root package SDK floor.

Shared-runner timings are informational. Do not claim redb engine performance from end-to-end numbers that also include Dart codec, FRB, Rust API, and storage overhead.

Performance work should isolate:

```text
Dart API
-> codec
-> FRB
-> Rust API
-> planner/index or redb
```

Do not add a fake Dart whole-box value cache merely to improve benchmark numbers.

## Binary-size policy

PR #12 established three-profile size measurements. PR #13 established same-commit reproducibility.

Cross-commit native-size regression policy remains a separate future hardening task and must not be invented inside query/index feature work.

## Developer workflow

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

Generated FRB bindings must remain checked in whenever the native API shape changes. The first planner slice does not change FRB shape.

## Current validation expectation

Every query/index PR should preserve the existing matrix:

```text
Minimum SDK / Ubuntu
  Flutter 3.22.0 + Dart 3.4.0
  analyze + tests

Current Flutter / Ubuntu
  format + analyze + tests

FRB generated bindings
  regenerate with flutter_rust_bridge_codegen 2.8.0
  fail on drift

Rust / Ubuntu + macOS + Windows
  rustfmt
  clippy -D warnings
  minimal tests
  encryption tests
  full tests

Native / Linux
  release build
  Dart -> FRB -> Rust -> redb round trip
  benchmark smoke

Native size / Linux
  minimal/encryption/full same-commit reproducibility

Platform Builds
  Android
  iOS --no-codesign
  macOS
  Linux
  Windows
```

## 0.3 next implementation sequence

After the first equality planner:

1. Keep scan/index equivalence as the prerequisite for every new planner rule.
2. Consider multiple-index candidate intersection for AND groups only if measurement justifies complexity.
3. Add range/index planning only with exact comparison and ordering equivalence tests.
4. Improve index prefix lookup to efficient redb range access without changing semantics.
5. Consider changing native scan internals to one redb read transaction after planner correctness is stable.
6. Add explicit `sortBy`/sort contract as a separate public API decision.
7. Add query/index benchmark scenarios only after semantic paths are proven equivalent.
8. Continue point-get/contains performance diagnosis independently.
9. Keep cross-commit size policy separate.
10. Keep Dart 3.13 native tree shaking deferred.

## Later roadmap

### 0.3.x

- expand planner/index-backed execution conservatively
- explicit sort contract / `sortBy`
- scan/index equivalence hardening
- Hive CE migration design/implementation

### 0.4.x

- production/package hardening
- controlled cross-commit native-size policy
- broader Flutter local-database comparison

### 0.9.x

Refresh the Hive Functional Parity Audit against the then-current Hive CE release and close every practical `Gap`.

### 1.0.0

- no practical parity gaps
- stable storage/API contract
- Web/IndexedDB strategy complete
- pub.dev release readiness

## Non-negotiable rules

- Never silently weaken storage durability for benchmark speed.
- Never introduce a Dart whole-box cache without an explicit coherency contract.
- Never leak encrypted indexed fields through plaintext persisted index keys.
- Never add another public native profile casually.
- Never raise the minimum Flutter/Dart floor incidentally.
- Never merge native API changes with stale FRB generated bindings.
- Never use an index as final truth; primary committed data remains authoritative.
- Keep README, this handoff, `CODE_WALKTHROUGH.md`, and `QUERY_INDEX_03.md` aligned with actual implementation state.
