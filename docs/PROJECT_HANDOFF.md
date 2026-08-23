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

Completed:

- **0.3 Query / Index / Migration**
- **0.4 Production Hardening PH-01..PH-05**
- **0.5 Performance / Read-path Optimization**
- **0.6 Query / Index + Encryption Hardening**
- **0.7 Query Ergonomics**
- **0.8 Rust-native API / Multi-frontend Foundation**

0.8 closure is recorded in `docs/RELEASE_AUDIT_08.md`.

### 0.9 Conformance & Startup Maturity

Current sequence:

```text
PR1 — reusable cross-frontend storage conformance test kit                   merged
PR2 — schema/index config fingerprint design + correctness guards            current
PR3 — cold-open/reopen benchmark; runtime fast path only if evidence justifies
PR4 — cross-frontend closure audit + docs/version sync
```

PR2's current design conclusion is intentionally conservative: do not persist a configuration fingerprint merely to hash the already-authoritative `index_definitions` table. Dxtr_Box has no consumer-supplied desired schema/index manifest at open time and currently performs no automatic schema/index reconciliation or rebuild pass that such a hash could skip.

PR3 must therefore profile the existing startup/reopen path before introducing durable metadata or runtime shortcuts. An evidence-backed no-op runtime decision is acceptable and preferable to speculative state.

See:

- `docs/CONFORMANCE_09.md`
- `docs/CONFIG_FINGERPRINT_DECISION_09.md`

## Architecture after 0.8

Required dependency direction is implemented:

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

## Cross-frontend conformance

0.8 established bidirectional same-file compatibility with `rust/tests/cross_frontend_compat.rs`:

```text
Rust-native write -> close -> FRB-adapter read
FRB-adapter write -> close -> Rust-native read
```

0.9 PR1 adds a reusable internal `StorageBoxContract` under `rust/tests/support/` and runs the same CRUD/batch/deletion semantics against both frontends. The initial contract covers missing-key behavior, put/get/contains, overwrite, bulk put, `get_all` ordering/duplicate/miss behavior, key enumeration, delete/delete-all, clear, and final empty state.

PR2 adds full-profile index-configuration guards across both frontends so future startup work cannot accidentally replace the dynamic-first index lifecycle with implicit schema registration.

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

Do not compare runs from different machines, build modes, record counts, or workload settings as a speedup ratio.

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

## 0.9 fingerprint/startup rule

Do not introduce a schema/index fingerprint unless there is an independently meaningful expected configuration to compare with durable state and a measured reconciliation cost to skip.

A future fingerprint must never bypass:

- `dxtr_box/1` format validation;
- encryption metadata/key validation;
- reduced-profile safety checks;
- authoritative fallback on missing/unknown/mismatched metadata.

Any durable fingerprint must be deterministic, versioned, transactionally updated with the configuration it summarizes, compatible with old boxes that lack it, and justified by cold-open/reopen evidence.

## Non-goals retained

Do not turn 0.9 into:

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

## Post-0.9 candidates

Consider later, only with evidence:

1. broader typed metadata only if `BoxField<T>` proves useful while dynamic APIs stay first-class;
2. capability abstractions only when multiple execution variants justify them;
3. user-facing end-to-end benchmark scenarios;
4. an explicit GPUI consumer integration project outside the core package if needed;
5. public conformance-kit extraction only if downstream frontend/adapter authors need it.

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
