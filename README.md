# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a Rust/redb-backed local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. Both frontends share the same authoritative Rust storage/query core, `dxtr_box/1` durable format, ACID persistence, authenticated encryption, native queries, persisted indexes, and batch reads. No model code generation is required.

> Status: **0.10 Real-world Workload Evidence is complete.** 0.10 adds deterministic application-shaped workload fixtures, equivalent Dart/FRB and Rust-native scenario runners, machine-readable JSONL evidence, and CI artifacts with toolchain metadata. Results are diagnostic boundary evidence, not marketing leaderboard claims. The package remains pre-1.0; public API and storage format are not yet declared stable.

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
package version = 0.10.0-dev.1
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
```

See `docs/CODE_WALKTHROUGH.md`, `docs/PROJECT_HANDOFF.md`, and `docs/RELEASE_AUDIT_010.md` for current architecture and milestone evidence.
