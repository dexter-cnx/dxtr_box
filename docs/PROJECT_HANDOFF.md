# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 product claim is **functional replacement for practical Hive/Hive CE local-database workloads**, not source-level/drop-in API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate: any practical capability classified as `Gap` blocks the 1.0 claim.

## Current snapshot — 0.3 query/index foundation

PR #14 implements the first executable 0.3 query/index slice on top of the already validated native foundation.

Current public/native capabilities:

- Public Dart facade: `DxtrBox`, `Box`, `BoxEvent`.
- Minimum compatibility floor: Dart >= 3.4.0 / Flutter >= 3.22.0, verified by dedicated CI.
- MessagePack codec for dynamic Flutter values.
- Rust `redb = 2.1.0` engine, one `{box}.dxtr` file per box.
- Transactional CRUD/bulk CRUD/lifecycle operations.
- Explicit `compact()` maintenance.
- Native cross-handle watch fan-out through FRB streams.
- Persisted per-box encryption using Argon2 + ChaCha20Poly1305.
- Explicit transactional plaintext -> encrypted migration.
- Process-level crash/reopen durability coverage for acknowledged commits.
- Three public native profiles only: `minimal`, `encryption`, `full`.
- Linux native-size baseline + same-commit reproducibility gate.
- Hive CE benchmark smoke harness; timings remain informational.
- Checked-in FRB 2.8 bindings with generated-drift CI.
- Android/iOS/macOS/Linux/Windows example build coverage.
- Root Makefile for preflight, native, query/index, benchmark, profile, and platform workflows.

PR #14 adds:

- `BoxQuery`, `QueryFilter`, `QueryComparison`, `QueryGroup`, query operator enums, and `IndexDefinition`.
- `Box.query(...)` using **one FRB call per query**.
- Rust native scan evaluation with dotted nested-field lookup.
- comparison operators: equality/inequality, greater/less comparisons, `between`, null checks.
- AND/OR boolean groups.
- deterministic record-key ordering before pagination.
- native scan support for plaintext and encrypted boxes.
- persisted `index_definitions` + `index_entries` tables under `full`.
- index create/backfill/list/drop lifecycle.
- transactional index maintenance coupled to `put`, `putAll`, `delete`, `deleteAll`, and `clear`.
- encrypted boxes explicitly reject persisted index creation until a secure encrypted-index representation exists.
- plaintext -> encrypted migration rejects boxes that still have persisted index definitions.

The query planner does **not** consume persisted indexes yet. Native scan remains the authoritative execution path.

## Current validation state

PR #14 final implementation was green on the normal CI and Platform Builds workflows before the final documentation-only refresh.

Validation surface:

```text
Minimum SDK / Ubuntu
  Flutter 3.22.0 + Dart 3.4.0
  pub get -> analyze -> tests

Current Flutter / Ubuntu
  format -> analyze -> unit tests

FRB generated bindings / Ubuntu
  regenerate with flutter_rust_bridge_codegen 2.8.0
  fail on drift

Native / Linux
  release build
  Dart -> FRB -> Rust -> redb round trip
  encrypted close/reopen
  plaintext -> encrypted migration
  watch / deleteAll / compact integration

Rust / Ubuntu + macOS + Windows
  rustfmt
  clippy -D warnings
  minimal profile tests
  encryption profile tests
  full profile tests
  query/index integration in full

Native size / Linux x86_64
  minimal/encryption/full release measurements
  repeated same-commit measurements
  zero-byte-spread reproducibility gate

Platform Builds
  Android
  iOS --no-codesign
  macOS
  Linux
  Windows
```

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

`full` remains the default production build used by normal Flutter/Cargokit integration.

Do **not** add a fourth public query profile. Internal optional dependencies required by full-profile query/index work are allowed; currently `rmpv` is included through `full`.

Reduced profiles retain a stable FRB-facing API and fail explicitly when a capability requires `full`.

## Minimum SDK policy

Current floor:

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

Do not raise this floor casually. Dependency/toolchain upgrades that require a newer SDK are explicit compatibility decisions.

Dart 3.13 recorded-use/native tree shaking remains future-only. It must not become required for correctness or force the current minimum upward.

## Native naming/build invariant

FRB and Cargokit must agree on:

```text
rust_lib_dxtr_box
```

Cargo package/lib name, `rust_builder/`, generated loader, and built artifact stem must remain aligned.

The root Flutter package is the Dart-facing facade. `rust_builder/` is the sole native build owner; do not reintroduce duplicate root platform FFI scaffolding.

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

Full-profile query/index adds:

```text
index_definitions
index_entries
```

Primary `data` is always authoritative. Secondary indexes are derived state and must never become the sole copy of user data.

## Mutation atomicity invariant

For primary data + persisted indexes:

```text
put / putAll / delete / deleteAll / clear
  -> compute required index changes
  -> update primary DATA
  -> update derived index entries
  -> same redb write transaction
  -> one commit
  -> emit public/native watch events after commit only
```

A committed mutation must never leave persisted indexes describing a different committed state than primary data.

Index creation also backfills and persists definition + derived entries atomically.

## Query architecture

Public execution path:

```text
Box.query(BoxQuery)
  -> serialize query AST with DxtrCodec
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> Rust decode query once
  -> enumerate committed records
  -> decrypt record if needed
  -> decode MessagePack value
  -> dotted nested-field lookup
  -> comparison / boolean-group evaluation
  -> deterministic key ordering
  -> offset / limit
  -> one FRB response containing matched key + payload records
  -> Dart decode result payloads
```

Important invariant: **one FRB call per query, not one FRB call per record**.

Current internal scan shape still uses key enumeration + per-record native reads rather than one redb read transaction spanning the full scan. That is a future performance/architecture improvement, not a semantic blocker.

Legacy `Box.where(predicate)` remains Dart-side and must not be confused with the declarative native engine.

## Persisted index architecture

Public Dart API:

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-status', field: 'status'),
);

final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-status');
```

Current first-slice constraints:

- named index;
- one dotted field path;
- scalar values only;
- no uniqueness contract;
- no composite index;
- no full text;
- no list expansion;
- no custom collation;
- plaintext boxes only for persisted indexes.

Index entry encoding uses a binary composite representation rather than delimiter concatenation.

## Encrypted query/index security policy

Encrypted boxes **may use native scan query**.

Encrypted boxes **may not create persisted secondary indexes yet**.

Reason: persisting plaintext-derived scalar keys would leak values that primary storage protects with encryption.

Do not bypass this rejection for convenience. A secure encrypted-index representation must be designed explicitly.

Also, plaintext -> encrypted migration is rejected while persisted index definitions exist. This prevents migration from producing encrypted primary data beside plaintext-derived index state.

## Encryption architecture

Metadata persists storage format and encryption mode. Encrypted boxes use a unique random salt, Argon2 key derivation, encrypted key-check sentinel, and ChaCha20Poly1305 values with fresh nonces and record-key AAD.

Wrong keys, tampering, and swapped ciphertext are rejected before plaintext reaches Dart.

Plaintext data is never silently reinterpreted as encrypted.

## Plaintext -> encrypted migration

Public API:

```dart
await DxtrBox.encryptBox(
  'settings',
  encryptionKey: 'correct horse battery staple',
);
```

Migration requires no live handles and performs value rewrite + encryption metadata transition atomically in one redb write transaction.

Additional 0.3 guard: migration rejects boxes with persisted indexes until encrypted index semantics exist.

## Native watch/event ordering

```text
Dart mutation
  -> FRB
  -> redb write transaction
  -> primary/index changes
  -> commit succeeds
  -> Rust emits NativeBoxEvent
  -> FRB stream
  -> open Box handles
```

Failed writes do not emit successful public events.

For encrypted boxes, event payloads still represent the public plaintext MessagePack value after storage commit; encryption remains an at-rest storage concern.

## Benchmark policy

The separate `benchmark/` package compares equal logical workloads with Hive CE without raising the root package SDK floor.

Existing shared-runner measurements are informational only. Do not make claims that redb itself is hundreds of times slower based on the old end-to-end microbenchmark: those numbers include Dart serialization, FRB overhead, Rust API work, and storage work.

Performance investigation should isolate:

```text
Dart API
  -> codec
  -> FRB boundary
  -> Rust API
  -> redb
```

Do not add a fake Dart whole-box value cache merely to improve benchmark numbers unless a coherent lifecycle/coherency contract is deliberately designed.

## Binary-size policy

PR #12 established the three profile measurements. PR #13 established same-commit reproducibility.

Cross-commit binary-size regression policy remains a separate future hardening task. Do not block query/index work on inventing that policy, and do not silently introduce a threshold inside feature work.

## Developer workflow

Preferred Make targets:

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

Generated FRB bindings must remain checked in whenever native API shape changes.

## 0.3 next implementation sequence

After PR #14:

1. Add an explicit native query planner.
2. Define planner eligibility for the first scalar persisted-index operators.
3. Add scan-vs-index equivalence tests before enabling index-backed execution broadly.
4. Preserve deterministic ordering/pagination independent of whether scan or index is selected.
5. Keep encrypted persisted indexes disabled until a non-leaking representation is designed.
6. Consider improving native scan to use one redb read transaction after planner correctness is established.
7. Add query/index benchmark scenarios only after semantic equivalence is proven; do not optimize against incorrect behavior.
8. Continue layered `point_get` / `contains` performance diagnosis independently.
9. Keep cross-commit size-budget policy separate.
10. Keep Dart 3.13 tree shaking deferred.

## Later roadmap

### 0.3.x

- planner/index-backed query execution
- explicit sort contract / `sortBy`
- scan/index equivalence hardening
- Hive CE migration design/implementation

### 0.4.x

- production/package hardening
- controlled cross-commit native-size policy
- broader comparison with other Flutter local databases

### 0.9.x

Execute the full Hive Functional Parity Audit against the then-current Hive CE release and close every practical `Gap`.

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
- Keep README, this handoff, `CODE_WALKTHROUGH.md`, and query/index design docs aligned with actual implementation state.
