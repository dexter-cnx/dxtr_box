# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter, forged in Rust. By Dxtr.**

Dxtr_Box is a compact Flutter-facing local database backed by Rust/redb, with durable native storage, declarative query/index execution, authenticated encryption, and simple box-style ergonomics.

It is **not** positioned as a Hive/Hive CE replacement. Hive CE remains an optional migration source, compatibility reference, and benchmark peer.

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

## Milestone state

Closed:

- **0.3 Query / Index / Migration** — complete.
- **0.4 Production Hardening PH-01..PH-05** — complete.
- **0.5 Performance / Read-path Optimization** — complete.
- **0.6 Query / Index + Encryption Hardening** — complete.

### 0.7 Query Ergonomics

Implementation PRs are merged:

```text
PR #44 — fluent queryWhere/comparison/AND/OR/grouping builder
PR #45 — orderBy/offset/limit + bound terminal find()
PR #46 — optional BoxField<T> typed metadata + functional API naming
PR4    — README/examples/API equivalence/compatibility closure (current)
```

0.7 is complete when this closure PR merges with the full quality bar green.

Normative design: `docs/QUERY_ERGONOMICS_07.md`.
Closure record: `docs/RELEASE_AUDIT_07.md`.

## Primary Dart API after 0.7

Use functional names for ordinary API/domain symbols:

```text
Box
BoxStore
BoxCodec
BoxQuery
BoxQueryBuilder
BoxField<T>
NativeBoxApi
FrbNativeBoxApi
UnavailableNativeBoxApi
BoxStoreMigrationInternals
```

Package/durable identities intentionally retain the product string:

```text
dxtr_box
rust_lib_dxtr_box
.dxtr
dxtr_box/1
@dxtr:* durable wire tags
```

`DxtrBox` remains a deprecated source-compatibility shim. Old codec/native seam names remain only where compatibility requires them. New implementation, examples, and documentation should use functional names.

## 0.7 query authoring contract

String-path authoring remains first-class:

```dart
final rows = await box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

Optional typed metadata:

```dart
const status = BoxField<String>('status');
const age = BoxField<int>('profile.age');
const name = BoxField<String>('name');

final rows = await box
    .queryWhereField(status).equals('active')
    .andField(age).gte(18)
    .orderByField(name)
    .limit(20)
    .find();
```

Standalone composition remains AST-only:

```dart
final query = BoxQueryBuilder
    .where('score').between(50, 100)
    .orderBy('score', descending: true)
    .limit(20)
    .build();
```

Direct `Box.query(BoxQuery)` remains first-class for advanced/dynamic composition.

### Query invariants

The fluent and typed APIs are authoring layers only:

```text
string/typed fluent authoring
  -> existing BoxQuery / QueryFilter AST
  -> existing serialization / FRB
  -> existing Rust planner/indexes
  -> authoritative primary-record recheck
```

0.7 does not add:

- a second query AST;
- Dart-side filtering or sorting;
- a second native query engine;
- automatic index creation;
- mandatory schemas;
- model/entity code generation;
- runtime reflection;
- storage-format changes;
- native-profile changes.

`findFirst`, `exists`, and `count` remain deferred until efficient native-backed operations exist. Do not implement them by materializing full result sets in Dart.

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
- Fluent 0.7 string-path query authoring.
- Optional `BoxField<T>` typed query metadata.
- Plaintext persisted scalar indexes: equality, range, nested fields, deterministic selection, AND intersection.
- Encrypted persisted equality indexes under `full` using deterministic keyed BLAKE2b MAC tokens.
- Encrypted ordered/range predicates remain scan-backed.
- Deterministic semantic sorting before pagination.
- Self-contained publishable Flutter FFI plugin topology.
- Android/iOS/macOS/Linux/Windows staged consumer validation.
- Native-size baseline/stability/cross-commit regression policy.
- Four-engine local-database comparison harness plus read/query diagnostics.

## Hard correctness invariants

Primary `data` is authoritative. Persisted indexes are derived state.

Mutations keep primary data and index maintenance in the same redb write transaction; watch events publish only after commit.

Do not replace authoritative native reads with Dart metadata, a Dart whole-box cache, or an implicit long-lived read snapshot.

Encrypted reads always retain full AEAD authentication.

Encrypted persisted indexes:

```text
Equal                  -> keyed equality index may narrow candidates
GreaterThan            -> authoritative scan
GreaterThanOrEqual     -> authoritative scan
LessThan               -> authoritative scan
LessThanOrEqual        -> authoritative scan
Between                -> authoritative scan
```

For mixed `AND`, equality terms may narrow candidates; ordered/range terms are evaluated after authoritative decrypt/authenticate.

Encrypted index entries must never contain raw plaintext scalar bytes.

`dxtr_box/1` remains readable. Any storage-format change requires deliberate backward-read/migration evidence.

## 0.5 read-path evidence retained

Controlled boundary evidence:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

`Box.getAll` uses one native crossing and one redb read snapshot. Do not regress these paths opportunistically during later work.

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

Install the tracked formatting guard once per clone:

```bash
bash tool/install_git_hooks.sh
```

Full merge validation preserves:

- minimum Flutter/Dart compatibility;
- Dart/Rust/native tests;
- exact three native profiles;
- migration/query/crash-reopen regression;
- FRB generated-binding reproducibility;
- native-size policy;
- package/pub readiness;
- benchmark correctness/smoke;
- staged Android/iOS/macOS/Linux/Windows consumers.

## Next milestone — 0.8 Rust-native API / Multi-frontend Foundation

Start **only after 0.7 is merged to a clean `main`**.

Goal: evolve Dxtr_Box into a storage engine with a Dart frontend and a first-class native Rust frontend over one shared authoritative Rust storage core.

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

The Rust frontend must not wrap Dart or FRB. GPUI is only an expected consumer, not a Dxtr_Box dependency or architectural target.

### 0.8 Phase 1 — architecture audit

Before changing crate topology, document:

1. where authoritative storage behavior currently lives;
2. which modules/types are FRB-specific;
3. whether query/index/encryption domain types are reusable without FRB;
4. bridge DTOs that should become native Rust domain types;
5. serialization that exists only because Dart calls the engine;
6. errors currently flattened to strings for FRB;
7. whether the current Rust crate links cleanly as an `rlib`;
8. Flutter/FRB-specific dependencies/features;
9. minimum module/crate boundary changes required;
10. whether current Rust tests already exercise the engine without FRB initialization.

Prefer the smallest topology that creates real dependency separation. Do not create extra crates merely for architectural aesthetics.

### 0.8 Rust-native API direction

Use normal Rust conventions rather than mechanically copying Dart:

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

- structured `Result<T, DxtrBoxError>` errors;
- `Path` / `PathBuf`;
- explicit ownership/lifetime behavior;
- documented `Send` / `Sync` behavior;
- no forced Tokio commitment;
- no GPUI dependency.

Minimum meaningful Rust-native surface should cover existing engine capabilities only: open/create, CRUD, batch reads/iteration, canonical queries, sort/pagination, indexes, migration, encryption where supported, and close/flush semantics where required.

### One query engine across both frontends

```text
Dart query builder ----┐
                       ├----> canonical Rust query representation ----> planner
Rust query builder ----┘
```

Both frontends must share predicate semantics, planner, persisted-index selection, encrypted equality rules, encrypted range scan fallback, authoritative rechecks, sorting, offset, and limit behavior.

### 0.8 validation

Add external-consumer-style native Rust tests for:

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
```

Add cross-frontend compatibility evidence where practical:

```text
Rust API write -> Dart/FRB-compatible read
Dart/FRB-compatible write -> Rust API read
```

Both frontends must use the same `dxtr_box/1` database. There is no Rust-native storage format.

### Proposed 0.8 PR strategy

```text
PR1 — core/FRB boundary audit + Rust-native foundation
PR2 — Rust-native CRUD/query API + structured errors
PR3 — profiles/concurrency + native integration tests/examples
PR4 — cross-frontend validation + benchmark evidence + docs/milestone closure
```

Adjust only if the actual Rust tree shows a safer decomposition.

### 0.8 non-goals

Do not turn 0.8 into:

- GPUI integration;
- a GUI framework package;
- ORM/schema/model code generation;
- sync/CRDT/vector-clock infrastructure;
- networking/server database functionality;
- storage-format redesign;
- a query-engine rewrite;
- a new encryption design;
- a fourth native profile;
- a broad Dart API redesign.

## Post-0.7 maturity candidates

Later candidates only:

1. reusable conformance/storage-contract test kit;
2. schema/config fingerprint + startup fast path;
3. broader typed metadata only if `BoxField<T>` proves valuable while keeping dynamic APIs first-class;
4. capability abstractions only when multiple execution variants justify them;
5. user-facing benchmark scenarios rather than isolated microbenchmarks only.

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
