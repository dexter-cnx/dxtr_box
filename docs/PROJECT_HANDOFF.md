# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

Dxtr_Box is a compact Rust/redb local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. It is **not** positioned as a Hive/Hive CE replacement; Hive CE remains optional migration tooling, a compatibility reference, and a benchmark peer.

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

Closed before 0.8:

- **0.3 Query / Index / Migration** — complete.
- **0.4 Production Hardening PH-01..PH-05** — complete.
- **0.5 Performance / Read-path Optimization** — complete.
- **0.6 Query / Index + Encryption Hardening** — complete.
- **0.7 Query Ergonomics** — complete.

### 0.8 Rust-native API / Multi-frontend Foundation

Implementation sequence:

```text
PR1 — core/FRB boundary audit + Rust-native foundation                merged
PR2 — Rust-native CRUD/query API + structured errors                 merged
PR3 — profiles/concurrency + native integration tests/examples       merged
PR4 — cross-frontend validation + benchmark/docs/version closure     current
```

0.8 is complete only after PR4's full merge quality bar is green and PR4 is merged to `main`. The closure record is `docs/RELEASE_AUDIT_08.md`.

## Architecture after 0.8

Required dependency direction is now implemented:

```text
Dart API -> FRB adapter ----┐
                            ├-> shared authoritative Rust core -> redb
Rust API -------------------┘
```

The Rust frontend does not wrap Dart or FRB. GPUI remains only a potential downstream consumer and is not a Dxtr_Box dependency.

One canonical storage engine means one durable contract:

```text
{box}.dxtr
meta[format_version] = dxtr_box/1
@dxtr:* durable MessagePack tags where already defined
```

There is no Rust-native storage format or conversion step between frontends.

## Public Dart API

Consumers importing `package:dxtr_box/dxtr_box.dart` use:

```text
Box
BoxStore
BoxQuery
BoxQueryBuilder
BoxField<T>
```

`DxtrBox` remains exported in Dart only as a deprecated source-compatibility shim that forwards to `BoxStore`.

Dart query authoring remains dynamic-first with optional typed metadata:

```dart
final rows = await box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

`BoxField<T>` is metadata only. It does not introduce schema registration, code generation, reflection, automatic indexes, or a second query AST.

## Public native Rust API

Primary Rust-facing types:

```text
DxtrBox
BoxHandle
Record
IndexDefinition
DxtrBoxError
QueryBuilder / QueryValue / SortOrder under full
```

Representative use:

```rust
let db = DxtrBox::open(path)?;
let assets = db.box_("assets")?;
assets.put("asset-1", encoded_value)?;

let rows = assets
    .query()
    .where_("workplace_id")
    .equals("cnx")
    .order_by("captured_at", SortOrder::Descending)
    .limit(200)
    .find()?;
```

Rust conventions are intentional:

- structured `Result<T, DxtrBoxError>`;
- `Path` / `PathBuf` root handling;
- explicit handle ownership/close behavior;
- `Send + Sync` validation for native handles;
- synchronous API today, with no forced Tokio commitment.

External-consumer example: `rust/examples/native_consumer.rs`.

## Shared query/index contract

Both frontends converge onto one canonical Rust query representation and planner:

```text
Dart BoxQuery/Builder ----┐
                          ├-> canonical QuerySpec -> planner -> redb
Rust QueryBuilder --------┘
```

They share predicate semantics, index selection, encrypted equality behavior, encrypted range scan fallback, authoritative primary rechecks, deterministic sorting, offset, and limit.

Primary `data` remains authoritative. Persisted indexes are derived state and are maintained in the same redb write transaction as primary mutations.

Encrypted reads always retain full AEAD authentication. Encrypted ordered/range predicates remain scan-backed; only deterministic keyed equality tokens may narrow candidates under `full`.

## Cross-frontend evidence in PR4

`rust/tests/cross_frontend_compat.rs` validates both directions on real `.dxtr` files:

```text
Rust-native write -> close -> FRB-adapter read
FRB-adapter write -> close -> Rust-native read
```

It uses valid MessagePack payloads and performs no export/import or codec conversion between frontends. Because the contract is CRUD-only, it participates in the existing all-target tests for `minimal`, `encryption`, and `full`.

## 0.8 benchmark evidence

Run:

```bash
bash tool/multi_frontend_benchmark.sh
```

Equivalent logical workloads run through native Rust and Dart/FRB frontends:

```text
point get
100-key get_all / getAll
indexed equality query + descending sort + limit(50)
```

Evidence files:

```text
build/multi-frontend/rust-native.jsonl
build/multi-frontend/dart-frb.jsonl
```

These results are diagnostic boundary evidence, not marketing claims. Rust-native timing includes the Rust facade, shared core, validation/encryption/storage work. Dart/FRB timing additionally includes Dart async/public API work, codec work where applicable, generated bridge transport, and cross-runtime overhead.

Do not compare runs from different machines/build modes/workload settings as a speedup ratio.

## Retained 0.5 read-path evidence

Controlled point-read bridge work remains relevant:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

`Box.getAll` still uses one native crossing and one redb read snapshot. Do not regress these paths opportunistically.

## CI topology

Cheap local preflight:

```bash
make preflight
```

Install the tracked formatting guard once per clone:

```bash
bash tool/install_git_hooks.sh
```

Full merge validation preserves:

- format/analyze/tests;
- Flutter 3.22 / Dart 3.4 minimum compatibility;
- Rust minimal/encryption/full all-target tests;
- native integration;
- migration/query/index/crash-reopen regression;
- FRB generated-binding reproducibility;
- native-size policy;
- package/pub readiness;
- benchmark correctness/smoke;
- staged Android/iOS/macOS/Linux/Windows consumers.

PR4 adds cross-frontend compatibility to the Rust all-target profile matrix and provides a reproducible multi-frontend benchmark runner without weakening existing gates.

## 0.8 non-goals retained

Do not turn the closure into:

- GPUI integration;
- a GUI framework package;
- Tokio/runtime commitment;
- ORM/schema/model code generation;
- sync/CRDT/vector-clock infrastructure;
- networking/server database functionality;
- storage-format redesign;
- query-engine rewrite;
- encryption redesign;
- a fourth native profile;
- broad Dart API redesign.

## Post-0.8 candidates

Consider later, only with evidence:

1. reusable cross-frontend conformance/storage-contract test kit;
2. schema/config fingerprint and startup fast path;
3. broader typed metadata only if `BoxField<T>` proves useful while dynamic APIs stay first-class;
4. capability abstractions only when multiple execution variants justify them;
5. user-facing end-to-end benchmark scenarios;
6. an explicit GPUI consumer integration project outside the core package if needed.

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

Correctness, durability, authenticated encryption, cross-process/cross-frontend visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.
