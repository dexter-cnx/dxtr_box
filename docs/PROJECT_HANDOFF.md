# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter, forged in Rust. By Dxtr.**

Dxtr_Box is currently a compact Flutter-facing local database backed by Rust/redb, with durable native storage, declarative query/index execution, first-class authenticated encryption, and simple box-style ergonomics.

The planned post-0.7 direction is to evolve Dxtr_Box into a **multi-frontend storage engine** with both a Dart frontend and a first-class native Rust frontend over one shared authoritative Rust storage core. The Rust frontend must remain usable by normal Rust desktop/server/tooling applications without depending on Flutter, Dart, GPUI, or flutter_rust_bridge.

It is **not** positioned as a Hive/Hive CE replacement. Hive CE remains an optional migration source, compatibility reference, and benchmark peer; it does not define product scope or 1.0 success.

## Stable runtime/package contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Dart:                   >= 3.4.0 < 4.0.0
Flutter:                >= 3.22.0
flutter_rust_bridge:    2.8.0 exactly
redb:                    2.1.0
durable format:         meta[format_version] = dxtr_box/1
native profiles:        minimal | encryption | full
```

`full` remains the default. Do not add a fourth native profile. Dart 3.13 recorded-use/native tree shaking remains deferred unless explicitly reprioritized.

## Closed milestones

- **0.3 Query / Index / Migration** — complete.
- **0.4 Production Hardening PH-01..PH-05** — complete.
- **0.5 Performance / Read-path Optimization** — complete.
  - decomposed point-read cost;
  - changed tiny `get` / `contains_key` FRB entrypoints to generated sync dispatch while preserving async public Dart API;
  - added one-snapshot `Box.getAll`;
  - rejected reusable long-lived read sessions because redb read transactions are fixed snapshots and can become stale;
  - final comparison/closure audit merged.
- **0.6 Query / Index + Encryption Hardening** — complete.
  - PR #39 established the encrypted-index threat model and safe-default guard;
  - PR #40 added encrypted equality indexing with keyed BLAKE2b tokens plus planner polish;
  - PR #42 locked encrypted ordered/range predicates to authoritative scan-backed execution;
  - PR #43 merged the final closure/audit publication for the completed milestone state.
- **Change-aware Fast CI** — complete; affected expensive gates during Draft, full merge quality bar for Ready/non-draft work.

Normative 0.6 design record: `docs/QUERY_INDEX_ENCRYPTION_06.md`.
Closure record: `docs/RELEASE_AUDIT_06.md`.

## Active milestone — 0.7 Query Ergonomics

Design record: `docs/QUERY_ERGONOMICS_07.md`.

0.7 improves Dart query authoring without replacing the existing query engine or changing durable storage.

### PR1 — fluent predicate builder

PR #44 implements the first 0.7 slice as a Dart-only authoring layer over the existing `BoxQuery` / `QueryFilter` AST.

Accepted public entry points:

```dart
final query = box
    .queryWhere('status').equals('active')
    .and('age').gte(18)
    .build();

final users = await box.query(query);
```

Standalone composition is also supported:

```dart
final query = BoxQueryBuilder
    .where('score').between(50, 100)
    .build();
```

`Box` already has the legacy compatibility method:

```dart
Future<List<MapEntry<String, dynamic>>> where(
  bool Function(dynamic) test,
)
```

Dart does not support method overloading and instance members shadow same-named extensions, so 0.7 deliberately uses **`box.queryWhere(...)`** rather than breaking or dynamically weakening legacy `Box.where(predicate)`.

PR1 supports:

```text
equals / notEquals
gt / gte / lt / lte
between
isNull / isNotNull
and / or
andGroup / orGroup
build
```

Mixed `AND` / `OR` chains are explicitly left-associative. Use `andGroup` / `orGroup` when grouping must be explicit.

Architecture remains:

```text
Fluent Dart API
      |
      v
existing BoxQuery / QueryFilter AST
      |
      v
existing serialization / FRB
      |
      v
existing Rust planner + indexes + authoritative record checks
```

`Box.query(BoxQuery)` remains first-class for advanced/dynamic composition. The fluent API is additive, not a parallel query model.

PR1 intentionally stops at `build()` plus existing `box.query(query)` execution. It does **not** add Dart-side filtering/sorting, a second AST or wire representation, FRB changes, Rust execution changes, storage changes, native-profile changes, or dependencies.

Remaining 0.7 sequence:

```text
PR2 — orderBy/offset/limit/find ergonomics; native-backed convenience operations only where efficient
PR3 — optional DxtrField<T> typed field metadata; no mandatory codegen/schema
PR4 — README/examples/API equivalence/compatibility closure
```

Do not turn 0.7 into an ORM, SQL parser, schema framework, or Dart-side post-filtering layer. `exists()` / `count()` should only be exposed when backed by efficient native operations rather than materializing full result sets across FRB.

## Next milestone after 0.7 — 0.8 Rust-native API / Multi-frontend Foundation

0.8 starts **only after 0.7 is complete and merged to a clean `main`**. Do not mix the unfinished 0.7 query-ergonomics work with this architecture change.

### Product direction

Dxtr_Box should evolve from a Flutter/Dart-facing storage package with a Rust backend into a storage engine with two first-class frontends:

```text
Dart frontend
    |
    v
FRB adapter
    |
    v
shared Rust core
    |
    v
redb

Rust frontend
    |
    v
shared Rust core
    |
    v
redb
```

Required dependency direction:

```text
Dart API ----> FRB adapter ----┐
                              ├----> shared Rust core ----> redb
Rust API ---------------------┘
```

The Rust frontend must **not** wrap Dart or FRB. GPUI is only an expected consumer, not a dependency or architectural target.

### Intended responsibility boundaries

Exact crate names may change after the architecture audit; separation of responsibilities is the requirement.

Conceptual layers:

```text
dxtr_box_core
    storage engine
    canonical query representation + planner
    indexes
    encryption
    migration
    transactions
    durable dxtr_box/1 contracts

dxtr_box_rust
    ergonomic public native Rust API
    structured Rust errors
    Rust-friendly configuration
    CRUD/query/index/migration/encryption surface

dxtr_box_frb
    Dart <-> Rust transport adapter
    bridge DTO conversion
    Dart/FRB serialization boundary
    no authoritative storage semantics
```

Prefer the smallest topology that produces real dependency separation. A single crate with carefully separated modules/features remains acceptable if an audit shows extra crates would only add churn.

### Phase 1 — architecture audit before broad refactor

Before changing crate topology, inspect and document:

1. where authoritative storage behavior currently lives;
2. which modules/types are FRB-specific;
3. whether query/index/encryption domain types are already reusable without FRB;
4. bridge DTOs that should become native Rust domain types;
5. JSON/string/byte serialization that exists only because Dart calls the engine;
6. errors currently flattened to strings for FRB;
7. whether the current Rust crate can already link cleanly as an `rlib`;
8. Flutter/FRB-specific features and dependencies;
9. the minimum crate/module boundary changes required;
10. whether existing Rust tests already exercise the engine without FRB initialization.

Document findings before any broad file reshuffle. Avoid speculative modularization when the current layout already supports a clean Rust-native surface.

### Rust-native public API direction

The API should follow normal Rust conventions rather than copying Dart syntax mechanically. Target ergonomics may resemble:

```rust
let db = DxtrBox::open(path)?;
let assets = db.box_("assets")?;

let rows = assets
    .query()
    .where_("workplace_id")
    .equals(workplace_id)
    .order_by("captured_at", SortOrder::Descending)
    .limit(200)
    .find()?;
```

Prefer:

- `Result<T, DxtrBoxError>`;
- enums/config structs over magic strings where practical;
- `Path` / `PathBuf`;
- explicit ownership/lifetime behavior;
- borrowed values where useful;
- iterators where they improve ergonomics without changing semantics;
- documented `Send` / `Sync` behavior.

Minimum meaningful Rust-native surface should cover existing engine capabilities only:

```text
open/create database
open/create box
get / put / delete / contains
batch get or equivalent iteration
canonical query execution
Rust-friendly query builder where sensible
sort / offset / limit
index create/list/drop and existing planner use
migration
encryption configuration when selected profile supports it
close/flush semantics if required by the engine
```

Do not invent unrelated capabilities merely to make the native API look richer.

### Error model

The authoritative Rust contract must use structured errors rather than flattened strings. Direction:

```rust
pub enum DxtrBoxError {
    Storage(...),
    Serialization(...),
    Query(...),
    Migration(...),
    Encryption(...),
    InvalidArgument(...),
    Corruption(...),
}
```

Use `thiserror` where appropriate and compatible with dependency policy. FRB may translate structured errors to the representation required by the existing Dart API, but string errors must not become the core contract.

### One query engine across both frontends

There must never be separate Dart and Rust query engines.

Target:

```text
Dart query builder ----┐
                       ├----> canonical Rust query representation ----> planner
Rust query builder ----┘
```

Both frontends must share the exact same:

- predicate semantics;
- planner;
- persisted-index selection;
- encrypted equality-index rules;
- encrypted ordered/range scan fallback;
- authoritative primary-record recheck;
- semantic ordering;
- offset/limit behavior.

Add AST-equivalence/canonical-request tests where useful.

### Feature/profile requirements

Native profiles remain exactly:

```text
minimal
encryption
full
```

Do not add a fourth profile. A plain Rust consumer should be able to select the appropriate capability set without dragging unnecessary Flutter/FRB-specific dependencies into its binary where avoidable.

Investigate clean dependency separation first; do not assume a multi-crate workspace is automatically better.

### Threading / concurrency contract

0.8 must document and test enough native behavior for UI, desktop, server, and tooling consumers to use the engine safely without framework-specific integration.

Establish:

- whether database handles are `Send`;
- whether database handles are `Sync`;
- whether box handles are `Send` / `Sync`;
- which operations may block;
- transaction concurrency rules;
- whether heavy queries should execute on worker threads;
- whether redb transactions remain internal or become exposed;
- current cancellation behavior, if any;
- whether handles may safely live in long-lived application state.

Do not add GPUI or commit to Tokio merely to satisfy this contract.

### Native and cross-frontend validation

Add external-consumer-style Rust tests covering at least:

```text
open
put/get/delete
reopen
query
index
sorting
pagination
migration
encryption when enabled
existing crash/reopen-sensitive invariants where practical
```

Add cross-frontend compatibility tests where useful:

```text
Rust API write -> Dart/FRB-compatible read
Dart/FRB-compatible write -> Rust API read
```

Both frontends must operate on the same `dxtr_box/1` database. There is no Rust-native storage format.

### Standalone Rust example

Provide a small UI-framework-independent native consumer, e.g. `examples/rust_native/`, demonstrating:

```text
open
put
get
query
close/reopen
```

A GPUI consumer belongs in another repository/project later, not inside Dxtr_Box.

### Benchmark implications

Extend benchmark evidence only where it isolates useful architecture costs:

- direct Rust `get`;
- direct Rust batch read;
- direct Rust query;
- equivalent Dart/FRB paths.

The purpose is to quantify:

```text
storage engine cost
vs
cross-runtime / bridge overhead
```

Do not turn this into a marketing benchmark or claim Rust is faster merely because it bypasses FRB. Preserve the existing benchmark correctness policy.

### Documentation/public-contract policy

During 0.8 keep synchronized:

- `README.md`;
- `docs/PROJECT_HANDOFF.md`;
- `docs/CODE_WALKTHROUGH.md`;
- `CHANGELOG.md`;
- a dedicated Rust-native architecture/API document such as `docs/RUST_NATIVE_API.md` when implementation begins.

The new Rust-native API may be explicitly labeled experimental during the first milestone. Do not prematurely promise 1.0 stability.

### Proposed PR strategy

Prefer approximately four reviewable PRs after the architecture audit confirms the safest boundaries:

```text
PR1 — core/FRB boundary audit + Rust-native foundation
PR2 — Rust-native CRUD/query API + structured errors
PR3 — profiles/concurrency + native integration tests/examples
PR4 — cross-frontend validation + benchmark evidence + docs/milestone closure
```

Adjust only if the actual Rust tree shows a safer decomposition.

Every PR must preserve Dart behavior, `dxtr_box/1`, current query/index/encryption semantics, migration/crash/reopen/read-path guarantees, and the exact three native profiles. Run formatting/checks before push, wait for CI, fix failures before continuing, and delete merged feature branches.

### 0.8 acceptance criteria

0.8 is complete only when:

```text
[ ] A normal Rust application can depend on Dxtr_Box without Dart.
[ ] Rust applications do not need flutter_rust_bridge to call the storage API.
[ ] Dart continues to use the same authoritative Rust storage core.
[ ] Dart and Rust frontends share planner/index/encryption/query semantics.
[ ] Both frontends read/write the same dxtr_box/1 database.
[ ] Native Rust API exposes structured errors.
[ ] Threading/Send/Sync behavior is documented.
[ ] minimal/encryption/full remain coherent.
[ ] Existing Dart public API/tests remain source-compatible and passing.
[ ] Native Rust integration tests exist.
[ ] Cross-frontend compatibility tests exist where practical.
[ ] A standalone Rust example exists.
[ ] Dxtr_Box has no GPUI dependency.
[ ] README/handoff/walkthrough/changelog are synchronized.
[ ] CI full quality bar passes.
```

### Explicit 0.8 non-goals

Do not turn the milestone into:

- GPUI integration;
- a GUI framework package;
- an ORM or code-generation system;
- sync/CRDT/vector-clock infrastructure;
- networking/server database functionality;
- Hive/Hive CE parity work;
- storage-format redesign;
- a query-engine rewrite;
- a new encryption design;
- a forced async runtime/Tokio commitment;
- a fourth native profile;
- a broad Dart API redesign.

## Current capabilities

- Rust/redb ACID storage, one `{box}.dxtr` file per box.
- MessagePack dynamic values.
- Transactional CRUD and bulk CRUD.
- Authoritative `get`, `containsKey`, and one-snapshot `getAll` reads.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Explicit plaintext-to-encrypted migration.
- Process crash/reopen durability coverage.
- Declarative `Box.query(BoxQuery)` with one native query call.
- Fluent 0.7 PR1 query authoring via `BoxQueryBuilder.where(...)` and collision-free `box.queryWhere(...)`.
- Plaintext persisted scalar indexes: equality, range, nested fields, deterministic selection, AND intersection.
- Encrypted persisted equality indexes under `full` using deterministic keyed BLAKE2b MAC tokens.
- Encrypted ordered/range predicates remain scan-backed.
- Deterministic semantic sorting before pagination; indexes currently narrow `where` only and do not satisfy ORDER BY.
- Self-contained publishable Flutter FFI plugin topology.
- Android/iOS/macOS/Linux/Windows staged consumer validation.
- Native-size baseline/stability/cross-commit regression policy.
- Four-engine local-database comparison harness plus read/query diagnostics.

## Hard correctness invariants

Primary `data` is authoritative. Persisted indexes are derived state.

Mutations keep primary data and index maintenance in the same redb write transaction; watch events publish only after commit.

Do not replace authoritative native reads with Dart metadata, a Dart whole-box cache, or an implicit long-lived read snapshot.

Encrypted reads always retain full AEAD authentication. Every encrypted-index candidate must:

```text
candidate key
  -> authoritative primary record
  -> ChaCha20Poly1305 authenticate/decrypt
  -> full predicate re-evaluation
  -> sort / offset / limit
  -> Dart result
```

Encrypted index entries must never contain raw plaintext scalar bytes.

`dxtr_box/1` remains readable. Any storage-format change requires deliberate backward-read/migration evidence.

## 0.5 read-path evidence retained

Controlled boundary evidence from 0.5:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

`Box.getAll` uses one native crossing and one redb read snapshot; hosted evidence reached about 8.59x improvement for 1,000 keys versus independent public `get` calls.

Do not regress these paths opportunistically during later work.

## Encrypted equality-index contract

Merged PR #40 introduced encrypted equality candidate narrowing:

```text
encrypted equality query
  -> query scalar canonicalization
  -> BLAKE2b keyed MAC token
     domain separated by index name + field
  -> exact token candidate lookup
  -> authoritative primary read
  -> authenticate/decrypt
  -> full predicate recheck
```

Accepted leakage:

- index/field names;
- candidate record identifiers;
- equality classes/frequency for repeated values;
- approximate indexed cardinality.

Not intentionally persisted:

- plaintext scalar values;
- semantic scalar ordering.

An earlier BLAKE3 implementation exceeded native-size policy and was replaced by BLAKE2 reuse already present through Argon2. Final measured full-profile Linux x64 evidence for PR2 was +30,432 bytes / +1.276%, within policy.

## Encrypted range decision

Merged PR #42 intentionally **does not** add encrypted persisted range ordering.

Production contract for encrypted boxes:

```text
Equal                  -> keyed equality index may narrow candidates
GreaterThan            -> authoritative scan
GreaterThanOrEqual     -> authoritative scan
LessThan               -> authoritative scan
LessThanOrEqual        -> authoritative scan
Between                -> authoritative scan
```

For mixed `AND`, equality terms may narrow candidates; ordered/range terms are evaluated after authoritative decrypt/authenticate.

Rejected for 0.6:

- sorting keyed hash/MAC bytes;
- plaintext/reversible sortable index bytes;
- order-preserving/order-revealing encryption;
- bucketized range tokens.

Reason: either incorrect ordering semantics, unacceptable order/distribution leakage, or complexity/storage/versioning cost disproportionate to current product value.

Decision record: `docs/ENCRYPTED_RANGE_DECISION_06.md`.

Regression guards include `rust/tests/encrypted_range_decision.rs` and `rust/tests/encrypted_range_planner_guard.rs`.

## 0.6 closure audit

The final acceptance matrix lives in `docs/RELEASE_AUDIT_06.md`.

PR #43 merged after the repository full quality bar was green, including:

- public API/storage contract checks;
- Dart/Rust/native tests;
- query/index/encryption regression coverage;
- migration and process crash/reopen coverage;
- FRB generated-binding reproducibility;
- exact three native profiles;
- native-size regression policy;
- package/pub readiness;
- benchmark correctness/smoke;
- staged Android/iOS/macOS/Linux/Windows consumers.

The merged state is **0.6 complete**.

## Benchmark policy

Benchmarks are engineering evidence, not marketing gates.

Important diagnostic targets:

```bash
make benchmark-comparison
make benchmark-query-index
make diagnose-point-read
make benchmark-read-path
make benchmark-batch-read
```

Hosted-runner timings are non-gating. Do not publish timing claims without the corresponding benchmark run, methodology, dataset size, and correctness validation.

## CI topology

```text
change detection
      |
      v
   Fast CI
      |
      +--> affected expensive validation during Draft iteration
      |
      v
Merge Gate / full quality bar
```

Cheap local preflight:

```bash
make preflight
```

### Local pre-push formatting guard

PR #44 adds a lightweight repository hook to prevent formatting-only CI failures from reaching GitHub.

One-time setup per clone:

```bash
bash tool/install_git_hooks.sh
```

This configures:

```text
core.hooksPath = .githooks
```

`.githooks/pre-push` is tracked as executable (`100755`). On push it requires a clean tree/index, runs the repository's canonical `make format`, and stops the push if formatting changed tracked files so the developer can review and commit those changes. It never auto-adds, auto-commits, or discards changes.

The hook is convenience only; CI `format-check` remains mandatory because hooks can be bypassed.

Full merge validation must preserve:

- minimum Flutter/Dart compatibility;
- Dart/Rust/native tests;
- exact three native profiles;
- migration/query/crash-reopen regression;
- FRB generated-binding reproducibility;
- native-size policy;
- package/pub readiness;
- staged Android/iOS/macOS/Linux/Windows consumers.

## Post-0.7 maturity candidates

Datum-inspired ideas retained for later evaluation:

1. reusable conformance / storage-contract test kit;
2. schema/config fingerprint + startup fast path;
3. broader typed schema/query metadata only if `DxtrField<T>` proves valuable while keeping the dynamic box API first-class;
4. capability abstractions only when multiple execution variants justify them;
5. user-facing benchmark scenarios rather than isolated microbenchmarks only.

Explicitly not adopted without a separate product-direction decision:

- built-in cloud/offline synchronization;
- backend sync adapters;
- pending-operation replication queues;
- vector clocks;
- CRDT collections/text;
- generic local-first application framework behavior.

## Deferred unless explicitly reprioritized

- Dart 3.13 recorded-use/native tree shaking;
- ORM/model code generation;
- built-in cloud replication/sync;
- general schema framework;
- index-backed ORDER BY unless evidence justifies complexity;
- LazyBox/direct `.hive` parsing;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB strategy.

## Working rule

Correctness, durability, authenticated encryption, cross-process visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.
