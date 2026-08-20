# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a Rust/redb-backed local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. Both frontends share the same authoritative Rust storage/query core, `dxtr_box/1` durable format, ACID persistence, authenticated encryption, native queries, persisted indexes, and batch reads. No model code generation is required.

> Status: **0.8 Rust-native API / Multi-frontend Foundation is at closure PR.** PR1 established the shared-core boundary, PR2 added the Rust-native CRUD/query API, PR3 validated profiles/concurrency and added a native consumer example, and PR4 adds cross-frontend compatibility plus benchmark evidence and final documentation/version synchronization. The package remains pre-1.0; public API and storage format are not yet declared stable.

## Key features

- One Rust/redb ACID storage engine shared by Dart/FRB and native Rust frontends.
- Async box-style Dart CRUD plus idiomatic `Result<T, DxtrBoxError>` Rust APIs.
- Authoritative optimized point reads and one-snapshot `getAll` / `get_all`.
- Declarative native queries with nested fields, groups, sort, offset, and limit.
- Fluent Dart query builder and native Rust query builder over one canonical planner.
- Optional `BoxField<T>` typed Dart field-path metadata without schema/codegen/ORM requirements.
- Persisted plaintext equality/range indexes.
- Encrypted equality indexes using domain-separated keyed BLAKE2b tokens under `full`.
- Argon2 + ChaCha20Poly1305 authenticated encryption.
- Native cross-handle watch events through Flutter Rust Bridge.
- Explicit plaintext-to-encrypted migration and optional Hive CE migration tooling.
- Android, iOS, macOS, Linux, and Windows staged Flutter consumer validation.
- Rust `rlib` consumer support with no Dart/FRB dependency direction.
- Cross-frontend storage compatibility tests and reproducible multi-frontend diagnostics.

## Compatibility

```text
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

Use `BoxStore` as the primary Flutter/Dart storage facade:

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

`DxtrBox` remains available in Dart only as a deprecated source-compatibility shim. New Dart code and documentation should use `BoxStore`.

## Rust-native API

The Rust frontend exposes normal Rust ownership/error conventions over the same storage engine:

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

See `rust/examples/native_consumer.rs` for the external-consumer-style example.

## Encryption

```dart
final secure = await BoxStore.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);

await secure.put('token', 'secret');
await secure.close();
```

Encrypted boxes require the same key on reopen. Encrypted reads retain full AEAD authentication. Plaintext-to-encrypted conversion is explicit and transactional.

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

Supported comparisons include `equals`, `notEquals`, `gt`, `gte`, `lt`, `lte`, `between`, `isNull`, `isNotNull`, AND/OR, and grouped AND/OR composition. Mixed chains are left-associative; use explicit groups when precedence matters.

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

The Dart fluent/typed layers and the Rust-native builder execute through the same canonical Rust query representation and planner. There is no Dart-side query engine and no Rust-only query engine.

## Query execution guarantees

- one native call per executed declarative Dart query;
- dotted nested fields;
- deterministic semantic sorting before pagination;
- one redb read snapshot for planner, primary reads, and sort inputs;
- plaintext equality/range persisted-index narrowing under `full`;
- encrypted equality persisted-index narrowing under `full`;
- encrypted ordered/range predicates remain authoritative scan-backed;
- authoritative primary-record re-read and full predicate re-evaluation after candidate narrowing.

Persisted indexes narrow `where` candidates only; they do not currently satisfy ORDER BY.

## Persisted indexes

```dart
await box.createIndex(
  IndexDefinition(name: 'by-age', field: 'profile.age'),
);

final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-age');
```

Primary data is authoritative. Index definitions and entries are derived state maintained transactionally with primary mutations.

Encrypted equality indexes intentionally leak equality classes/frequency for repeated indexed values plus index metadata and record identifiers. They do not persist raw plaintext scalar values or semantic scalar ordering. Encrypted ordered/range predicates stay scan-backed.

See `docs/QUERY_INDEX_ENCRYPTION_06.md` and `docs/ENCRYPTED_RANGE_DECISION_06.md`.

## Hive CE migration

Hive CE support is optional interoperability tooling, not the product identity or API target. Core `dxtr_box` has no runtime dependency on Hive CE.

```dart
final source = HiveCeMigrationSource(
  name: hiveBox.name,
  isOpen: () => hiveBox.isOpen,
  keys: () => hiveBox.keys,
  get: hiveBox.get,
);

final result = await migrateFromHiveCe(
  source,
  destinationName: 'settings_v2',
);
```

Migration preflights converted values, detects converted-key collisions, preserves source data, and writes through one destination transaction.

## Native feature profiles

Exactly three Rust capability profiles are supported:

| Profile | Cargo flags | Contract |
| --- | --- | --- |
| `minimal` | `--no-default-features` | CRUD + lifecycle + native watch |
| `encryption` | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| `full` | default | encryption + maintenance + query/index implementation |

Do not add a fourth profile merely for binary-size tuning.

## Cross-frontend compatibility

`rust/tests/cross_frontend_compat.rs` verifies both durable directions against the same database files:

```text
Rust-native write -> close -> FRB-adapter read
FRB-adapter write -> close -> Rust-native read
```

No export/import or format translation is involved. The test is part of the existing Rust all-target/profile matrix, so CRUD compatibility is exercised under `minimal`, `encryption`, and `full`.

## Multi-frontend benchmark evidence

Run the reproducible 0.8 diagnostic:

```bash
bash tool/multi_frontend_benchmark.sh
```

It runs equivalent logical workloads for native Rust and Dart/FRB and emits:

```text
build/multi-frontend/rust-native.jsonl
build/multi-frontend/dart-frb.jsonl
```

The matrix covers point `get`, 100-key batch read, and an indexed equality query with sort/limit. Treat results as boundary diagnostics, not marketing claims: Dart/FRB measurements include cross-runtime and Dart-side overhead that direct Rust measurements do not.

See `docs/RELEASE_AUDIT_08.md` for the exact workload and interpretation rules.

## Package architecture

```text
lib/        Dart API + generated FRB bindings
rust/       Rust crate / native library: rust_lib_dxtr_box
cargokit/   native build integration
android/
ios/
macos/
linux/
windows/
example/
```

The package identity `dxtr_box`, native library identity `rust_lib_dxtr_box`, `.dxtr` files, durable marker `dxtr_box/1`, and existing `@dxtr:*` wire tags are compatibility identities and intentionally retain the brand string.

## CI and validation

The merge quality bar covers:

- format/analyze/tests;
- Flutter 3.22 / Dart 3.4 minimum compatibility;
- exact `minimal | encryption | full` Rust profiles;
- native integration;
- Rust-native external integration/profile/concurrency coverage;
- migration/query/index/crash-reopen regressions;
- generated FRB reproducibility;
- native-size regression policy;
- package/pub dry-run;
- benchmark correctness smoke;
- Android/iOS/macOS/Linux/Windows staged consumers.

Install the repository pre-push formatting hook once per clone:

```bash
bash tool/install_git_hooks.sh
```

## Documentation

- `docs/RELEASE_AUDIT_08.md` — 0.8 closure, cross-frontend evidence, benchmark contract.
- `docs/RUST_NATIVE_ARCHITECTURE_AUDIT_08.md` — shared-core/native frontend architecture audit.
- `docs/RUST_NATIVE_PROFILES_CONCURRENCY_08.md` — profile and concurrency contract.
- `docs/PROJECT_HANDOFF.md` — current project state and next work.
- `docs/CODE_WALKTHROUGH.md` — current Dart/FRB/Rust execution paths.
- `docs/QUERY_ERGONOMICS_07.md` — fluent/typed Dart query design.

## Direction after 0.8

0.8 deliberately stops at the multi-frontend storage foundation. GPUI integration, ORM/model generation, cloud sync/networking, storage-format redesign, a fourth native profile, and a new query/encryption engine remain out of scope unless separately planned.
