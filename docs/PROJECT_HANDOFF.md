# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

Dxtr_Box is a compact Rust/redb local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. It is **not** positioned as a Hive/Hive CE replacement; Hive CE remains optional migration tooling, a compatibility reference, and a benchmark peer.

## Stable runtime/package contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Package version:         0.9.0-dev.1
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          meta[format_version] = dxtr_box/1
native profiles:         minimal | encryption | full
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
- **0.9 Conformance & Startup Maturity**

0.8 closure: `docs/RELEASE_AUDIT_08.md`.
0.9 closure: `docs/RELEASE_AUDIT_09.md`.

### 0.9 completed sequence

```text
PR1 — reusable cross-frontend storage conformance test kit                    merged
PR2 — schema/index config fingerprint decision + correctness guards           merged
PR3 — cold-open/reopen benchmark evidence; no runtime fast path justified     merged
PR4 — closure audit + docs/version synchronization                            current closure PR
```

0.9 conclusion: do **not** persist a schema/index fingerprint or add startup caching/fast-path machinery. There is no independent desired schema manifest to compare against persisted index definitions, and measured reopen cost remained below 1 ms p95 across the hosted Linux x64 matrix up to 10,000 records and 4 persisted indexes.

See:

- `docs/CONFORMANCE_09.md`
- `docs/CONFIG_FINGERPRINT_DECISION_09.md`
- `docs/STARTUP_BENCHMARK_09.md`
- `docs/RELEASE_AUDIT_09.md`

## Architecture

Required dependency direction:

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

`BoxField<T>` is authoring metadata only. It does not introduce schema registration, code generation, reflection, automatic indexes, or a second query AST.

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

The Rust API is synchronous today, uses structured `Result<T, DxtrBoxError>`, and has no Tokio commitment.

## Shared query/index contract

Both frontends converge onto one canonical Rust query representation and planner:

```text
Dart BoxQuery/Builder ----┐
                          ├-> canonical QuerySpec -> planner -> redb
Rust QueryBuilder --------┘
```

Primary records are authoritative. Persisted indexes are derived state and are maintained in the same redb write transaction as primary mutations.

Encrypted equality indexes may narrow candidates using deterministic keyed BLAKE2b MAC tokens under `full`; encrypted ordered/range predicates remain scan-backed. Authoritative primary decrypt/authenticate and predicate recheck remain mandatory.

## Cross-frontend conformance

0.8 established bidirectional same-file compatibility:

```text
Rust-native write -> close -> FRB-adapter read
FRB-adapter write -> close -> Rust-native read
```

0.9 adds reusable `StorageBoxContract` assertions against both frontends for missing keys, CRUD, overwrite, bulk put, ordered/duplicate-aware `get_all`, key enumeration, deletion, clear, and final empty state.

0.9 also adds full-profile index lifecycle guards proving dynamic create/list/drop/reopen semantics across Rust-native and FRB-adapter paths without schema registration.

## Startup evidence

Run standalone startup diagnostics with:

```bash
bash tool/startup_benchmark.sh
```

Matrix:

```text
records = 0 | 1,000 | 10,000
indexes = 0 | 1 | 4
```

Recorded metrics:

```text
first_open_us
reopen_p50_us
reopen_p95_us
reopen_max_us
```

Hosted Linux x64 evidence showed no material scale-linked startup regression and sub-1 ms reopen p95 across the matrix. Therefore no 0.9 runtime fast path was introduced.

Safety rules for the benchmark:

- `DXTR_BOX_STARTUP_ITERATIONS` must be positive;
- `DXTR_BOX_STARTUP_ROOT` is treated only as a parent directory;
- the runner removes only its dedicated `dxtr-box-startup-benchmark` child.

## Multi-frontend benchmark evidence

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
build/multi-frontend/startup.jsonl
```

Treat benchmark results as diagnostic boundary evidence, not marketing claims. Do not compare runs from different machines, build modes, record counts, or workload settings as direct speedup ratios.

## Retained read-path evidence

`Box.getAll` still uses one native crossing and one redb read snapshot. Point reads remain synchronous at the generated FRB boundary where established by 0.5. Do not regress these paths opportunistically.

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

## Fingerprint/startup rule after 0.9

Do not introduce a schema/index fingerprint unless there is an independently meaningful expected configuration to compare with durable state and a measured reconciliation cost to skip.

A future fingerprint or startup optimization must never bypass:

- `dxtr_box/1` format validation;
- encryption metadata/key validation;
- reduced-profile safety checks;
- authoritative fallback on missing/unknown/mismatched metadata.

## Non-goals retained

Do not turn post-0.9 work into:

- GPUI integration inside the core package;
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
