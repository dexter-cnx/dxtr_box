# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a Rust/redb-backed local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. Both frontends share the same authoritative Rust storage/query core, `dxtr_box/1` durable format, ACID persistence, authenticated encryption, native queries, persisted indexes, and batch reads. No model code generation is required.

> Status: **1.0.0 stable.** The 1.0 release freezes the existing public/package/durable contracts after contract guards, semantic regression coverage, staged five-platform published-consumer validation, migration/reopen evidence, and the 0.10 real-world workload evidence milestone. The durable format remains `dxtr_box/1`; 1.0 introduces no storage migration.

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
- Reproducible multi-frontend, startup/reopen, and real-world workload diagnostics.

## Compatibility

```text
package version = 1.0.0
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

0.9 added a reusable internal `StorageBoxContract` that runs the same CRUD/batch/deletion semantics against both frontends. It covers missing keys, put/get/contains, overwrite, bulk put, ordered `get_all` with duplicate preservation and miss omission, key enumeration, delete/delete-all, clear, and final empty state.

Full-profile guards also verify that dynamic index create/list/drop/reopen behavior remains shared across Rust-native and FRB-adapter paths without schema registration.

## Startup/reopen evidence

Run:

```bash
bash tool/startup_benchmark.sh
```

Matrix:

```text
records = 0 | 1,000 | 10,000
indexes = 0 | 1 | 4
```

Each case records `first_open_us`, `reopen_p50_us`, `reopen_p95_us`, and `reopen_max_us`.

Hosted Linux x64 evidence showed reopen p95 remaining below 1 ms across the matrix, including 10,000 records / 4 persisted indexes. Therefore 0.9 intentionally adds **no startup fast path, no startup cache, and no persisted configuration fingerprint**.

The benchmark rejects zero iterations and only removes its own dedicated child directory under any caller-supplied root.

## Multi-frontend benchmark evidence

Run:

```bash
bash tool/multi_frontend_benchmark.sh
```

Equivalent logical workloads run through native Rust and Dart/FRB and emit:

```text
build/multi-frontend/rust-native.jsonl
build/multi-frontend/dart-frb.jsonl
build/multi-frontend/startup-open.jsonl
```

The matrix covers point `get`, 100-key batch read, indexed equality query with sort/limit, and startup/reopen diagnostics. Treat results as diagnostic boundary evidence, not marketing claims.

## Real-world workload evidence

Run:

```bash
bash tool/real_world_workloads.sh
```

The 0.10 evidence suite runs deterministic `settings_session`, `catalog_workspace`, and `activity_event` scenarios through both Dart/FRB and Rust-native frontends. It emits three JSONL records per frontend plus logs and toolchain metadata under `build/real-world/`. CI reruns this evidence when benchmark definitions or production paths under `lib/**` or `rust/src/**` change.

Treat these results as diagnostic cross-frontend boundary evidence, not direct storage-engine speedup claims.

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

- `docs/RELEASE_AUDIT_100.md` — stable 1.0.0 release audit and compatibility boundary.
- `docs/RELEASE_CANDIDATE_EVIDENCE_10.md` — published-consumer, migration, and upgrade evidence matrix.
- `docs/PUBLIC_API_SEMANTIC_REGRESSION_10.md` — public query/API semantic regression inventory.
- `docs/RELEASE_READINESS_10.md` — 1.0 contract-freeze readiness policy.
- `docs/RELEASE_AUDIT_010.md` — 0.10 closure and real-world workload evidence.
- `docs/REAL_WORLD_WORKLOADS_010.md` — deterministic application-shaped workload contract.
- `docs/REAL_WORLD_CROSS_FRONTEND_010.md` — Dart/FRB vs Rust-native interpretation rules.
- `docs/PROJECT_HANDOFF.md` — current project state and maintenance rules.
- `docs/CODE_WALKTHROUGH.md` — current Dart/FRB/Rust execution paths.

## Direction after 1.0

Treat public Dart semantics, Rust root API, package/native identities, native profiles, and `dxtr_box/1` as compatibility-sensitive contracts. GPUI integration belongs in downstream consumer projects rather than the core package. ORM/model generation, cloud sync/networking, storage-format redesign without an explicit migration plan, a fourth native profile, speculative startup caching/fingerprinting, and broad query/encryption rewrites remain out of scope unless separately justified.
