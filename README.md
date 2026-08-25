# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a Rust/redb-backed local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. Both frontends share the same authoritative Rust storage/query core, `dxtr_box/1` durable format, ACID persistence, authenticated encryption, native queries, persisted indexes, and batch reads. No model code generation is required.

> Status: **1.1.0 stable.** 1.1 is a compatibility-preserving post-1.0 evidence release: stronger native concurrency/reopen coverage, Dart isolate/FRB concurrency evidence, hosted-registry consumer verification infrastructure, and reproducible native-size decision evidence. The durable format remains `dxtr_box/1`; 1.1 introduces no storage migration or SDK-floor increase.

## Key features

- One Rust/redb ACID storage engine shared by Dart/FRB and native Rust frontends.
- Async box-style Dart CRUD plus idiomatic `Result<T, DxtrBoxError>` Rust APIs.
- Optimized point reads and one-snapshot `getAll` / `get_all`.
- Declarative native queries with nested fields, groups, sort, offset, and limit.
- Fluent Dart query builder and native Rust query builder over one canonical planner.
- Optional `BoxField<T>` typed Dart field-path metadata without schema/codegen/ORM requirements.
- Persisted plaintext equality/range indexes.
- Encrypted equality indexes using domain-separated keyed BLAKE2b tokens under `full`.
- Argon2 + ChaCha20Poly1305 authenticated encryption.
- Explicit plaintext-to-encrypted migration and optional Hive CE migration tooling.
- Android, iOS, macOS, Linux, and Windows staged Flutter consumer validation.
- Rust `rlib` consumer support with no Dart/FRB dependency direction.
- Bidirectional same-file compatibility tests plus reusable cross-frontend conformance tests.
- Native concurrent reader/writer and Dart isolate/FRB shared-storage evidence.
- Reproducible multi-frontend, startup/reopen, native-size, and real-world workload diagnostics.

## Compatibility

```text
package version = 1.1.0
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
durable format = dxtr_box/1
```

The minimum SDK floor is validated in CI using Flutter 3.22.0 / Dart 3.4.0.

## Architecture

```text
Dart API -> FRB adapter ----┐
                            ├-> shared Rust core -> redb
Rust API -------------------┘
```

The Rust frontend never wraps Dart or FRB. GPUI is a possible downstream consumer, not a `dxtr_box` dependency.

## Dart API

```dart
await BoxStore.init();
final box = await BoxStore.open('settings');

await box.put('theme', 'dark');
final theme = await box.get('theme');
final selected = await box.getAll(['theme', 'missing', 'theme']);

await box.deleteAll(['theme', 'legacy']);
await box.compact();
await box.close();
```

`DxtrBox` remains available in Dart only as a deprecated source-compatibility shim. New Dart code should use `BoxStore`.

## Rust-native API

```rust
use rust_lib_dxtr_box::{DxtrBox, SortOrder};

let db = DxtrBox::open("./data")?;
let assets = db.box_("assets")?;

assets.put("asset-1", encoded_value)?;
let value = assets.get("asset-1")?;

let rows = assets
    .query()
    .where_("workplace_id")
    .equals("cnx")
    .order_by("captured_at", SortOrder::Descending)
    .limit(200)
    .find()?;

assets.close()?;
```

`DxtrBox`, `BoxHandle`, `Record`, `IndexDefinition`, and `DxtrBoxError` are native Rust-facing types. Query types are available under the `full` profile. The native frontend is synchronous today and does not impose a Tokio runtime.

## Fluent Dart queries

```dart
final users = await box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

Optional typed metadata remains available without making schemas mandatory:

```dart
const status = BoxField<String>('status');
const age = BoxField<int>('profile.age');

final users = await box
    .queryWhereField(status).equals('active')
    .andField(age).gte(18)
    .limit(20)
    .find();
```

The Dart fluent/typed layers and Rust-native builder execute through the same canonical Rust query representation and planner.

## Persisted indexes and encryption

Primary data is authoritative. Index definitions and entries are derived state maintained transactionally with primary mutations.

Plaintext indexes may narrow equality/range predicates. Encrypted equality indexes use deterministic keyed tokens and intentionally leak equality classes/frequency for repeated indexed values. Encrypted ordered/range predicates remain scan-backed, with authoritative primary decrypt/authenticate and predicate recheck.

## Native feature profiles

Exactly three Rust capability profiles are supported:

| Profile | Cargo flags | Contract |
| --- | --- | --- |
| `minimal` | `--no-default-features` | CRUD + lifecycle + native watch |
| `encryption` | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| `full` | default | encryption + maintenance + query/index implementation |

Do not add a fourth profile merely for binary-size tuning.

## Cross-frontend compatibility and conformance

Durable compatibility is verified in both directions:

```text
Rust-native write -> close -> FRB-adapter read
FRB-adapter write -> close -> Rust-native read
```

0.9 added a reusable internal `StorageBoxContract` that runs the same CRUD/batch/deletion semantics against both frontends. Full-profile guards verify that dynamic index create/list/drop/reopen behavior remains shared across Rust-native and FRB-adapter paths without schema registration.

## Concurrency evidence

1.1 strengthens executable concurrency evidence at both frontend boundaries:

- Rust-native tests guarantee reader/writer overlap across independent handles and verify concurrent mutations remain durable after reopen.
- Dart isolate tests require each isolate to initialize/open the same path independently, observe a committed peer write while both handles are active, close successfully, and only then allow the parent to reopen and verify all records.

This does not make `Box` instances transferable between isolates or define cross-isolate watch ordering, fairness, or lock-free semantics.

## Native-size decision evidence

The manual `Native Size Evaluation` workflow records Linux/macOS `minimal | encryption | full` artifacts together with generated `rust/Cargo.lock`, locked Cargo metadata, commit, and toolchain context. Tree-shaking or SDK-floor changes remain deferred until like-for-like evidence demonstrates both >=64 KiB absolute and >=3% relative savings while preserving compatibility/correctness gates.

## Startup/reopen evidence

Run:

```bash
bash tool/startup_benchmark.sh
```

The benchmark records first-open and reopen percentiles across 0/1,000/10,000 records and 0/1/4 indexes. Hosted Linux x64 evidence remained below 1 ms reopen p95 across the tested matrix, so no speculative startup cache or persisted fingerprint was added.

## Multi-frontend benchmark evidence

Run:

```bash
bash tool/multi_frontend_benchmark.sh
```

Equivalent logical workloads run through native Rust and Dart/FRB. Treat results as diagnostic boundary evidence, not marketing claims.

Latest hosted Linux x64 evidence on the 1.1 release line measured median point `get` at about **0.93 µs** through the public Rust-native frontend versus about **47.7 µs** through Dart/FRB. The same run measured `get_all(100)` at about **57.3 µs** versus **367.8 µs**, while an indexed query + sort + limit measured about **1.01 ms** versus **1.31 ms**.

This shape indicates that the main bottleneck for very small Flutter/Dart point reads is the **Dart async + generated FRB cross-runtime boundary**, not the underlying redb point lookup. As more useful work is performed per call, such as batch reads or indexed queries, that fixed boundary cost is amortized and the frontend gap narrows substantially. These numbers are diagnostic observations from one controlled runner/workload and must not be presented as a general storage-engine speedup or as an apples-to-apples comparison across different machines/build modes.

## Real-world workload evidence

Run:

```bash
bash tool/real_world_workloads.sh
```

The deterministic `settings_session`, `catalog_workspace`, and `activity_event` scenarios run through both Dart/FRB and Rust-native frontends. Treat these results as diagnostic cross-frontend boundary evidence, not direct storage-engine speedup claims.

## Hive CE migration

Hive CE support is optional interoperability tooling, not the product identity or API target. Core `dxtr_box` has no runtime dependency on Hive CE.

## CI and validation

The merge quality bar covers:

- format/analyze/tests;
- Flutter 3.22 / Dart 3.4 minimum compatibility;
- exact `minimal | encryption | full` Rust profiles;
- public/storage contract and semantic regression guards;
- native integration;
- cross-frontend compatibility/conformance;
- native and Dart-isolate concurrency evidence;
- migration/query/index/crash-reopen regressions;
- generated FRB reproducibility;
- native-size regression policy;
- package/pub dry-run;
- benchmark correctness smoke;
- real-world workload evidence for relevant production-path changes;
- Android/iOS/macOS/Linux/Windows staged consumers.

Install the repository pre-push formatting hook once per clone:

```bash
bash tool/install_git_hooks.sh
```

## Documentation

- `docs/RELEASE_AUDIT_110.md` — 1.1 closure audit and compatibility boundary.
- `docs/DART_ISOLATE_CONCURRENCY_EVIDENCE_11.md` — Dart isolate / FRB evidence.
- `docs/NATIVE_SIZE_DECISION_11.md` — native-size/tree-shaking decision evidence.
- `docs/CONCURRENCY_EVIDENCE_11.md` — native Rust concurrency evidence.
- `docs/POST_RELEASE_REGISTRY_VERIFICATION_11.md` — hosted-registry consumer verification policy.
- `docs/RELEASE_AUDIT_100.md` — stable 1.0 release audit.
- `docs/PROJECT_HANDOFF.md` — current project state and maintenance rules.
- `docs/CODE_WALKTHROUGH.md` — current Dart/FRB/Rust execution paths.

## Direction after 1.1

Treat public Dart semantics, Rust root API, package/native identities, native profiles, and `dxtr_box/1` as compatibility-sensitive contracts. Further runtime/tooling work should start from observed consumer or reliability needs with executable evidence. GPUI integration belongs in downstream consumer projects rather than the core package; speculative tree-shaking, Web support, migration extensions, or stronger cross-isolate semantics remain separate decisions rather than automatic scope.
