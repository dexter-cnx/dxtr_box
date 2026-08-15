# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.1.0 foundation / active development**. Public API and storage format are not stable yet.

## Why

Hive's original project is no longer a suitable foundation for new production work, while Dart-only box databases generally keep their hot data in Dart memory. `dxtr_box` targets Hive-like ergonomics while moving persistence, transactions, and heavy work into Rust.

## Design goals

- Hive-simple API.
- Functional replacement for practical Hive/Hive CE local-database workloads by 1.0.
- `redb` ACID storage engine.
- One file per box: `{base_path}/{box_name}.dxtr`.
- Thin Dart wrapper over Rust through Flutter Rust Bridge v2.
- MessagePack value encoding.
- Optional encryption with Argon2 + ChaCha20Poly1305.
- Android, iOS, macOS, Linux, Windows first; Web fallback later.
- No `build_runner` for normal usage.
- Avoid loading an entire box into Dart RAM.
- Aggressive native binary-size control, including Dart 3.13 `record_use` / native tree-shaking work.

## Intended API

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');

await box.put('theme', 'dark');
final theme = await box.get('theme');

await box.delete('theme');
await box.close();
```

Native reads are asynchronous by design: unlike Hive's in-memory read model, `dxtr_box` may perform real storage I/O and should not block Flutter's UI isolate.

## Engine

- Rust
- `redb = 2.1`
- `flutter_rust_bridge = 2.8`
- `rmp-serde`
- `once_cell` + `parking_lot`
- optional `argon2` + `chacha20poly1305`

## Engineering docs

- [Code walkthrough](docs/CODE_WALKTHROUGH.md) — Dart API -> codec -> FRB seam -> Rust API -> redb transaction flow.
- [Testing strategy](docs/TESTING.md) — Dart/Rust test matrix, local commands, CI gates, and deferred integration tiers.
- [Hive functional parity audit](docs/HIVE_FUNCTIONAL_PARITY.md) — 1.0 release gate for replacing practical Hive/Hive CE workloads.
- [Project handoff](docs/PROJECT_HANDOFF.md) — current implementation status and milestone sequencing.
- [CI workflow](.github/workflows/ci.yml) — Flutter analyze/test plus Rust host-matrix checks.

## Test suite

Current foundation coverage includes:

- Dart dynamic codec round trips and invalid-map validation.
- `Box`/`DxtrBox` behavior through an in-memory native API fake.
- real redb CRUD, clear, persistence-after-reopen, malformed `putAll`, unsafe box names, and delete-box behavior.
- Rust default and `encryption` feature test runs in CI.

The CI is intentionally not yet claiming five-platform Flutter builds: generated FRB bindings and native plugin scaffolds must be checked in and validated first.

## Roadmap

### 0.1.0 — MVP

- init / open
- put / get / delete / clear
- length / keys / values
- Android / iOS / macOS / Linux / Windows
- FRB code generation
- Rust + Flutter tests

### 0.2.0 — Hive parity foundation

- putAll / deleteAll
- deleteBox / boxExists
- encryption
- native `watch()` stream
- compact
- benchmark against `hive_ce`
- Cargo feature splitting for optional functionality

### 0.3.0 — Query & migration

- whereEquals / whereGreaterThan
- sortBy / limit
- secondary indexes
- migrateFromHiveCe

### 0.4.0 — Production hardening

- ACID crash tests
- five-platform CI
- binary-size regression checks
- Dart 3.13 native tree-shaking investigation using `record_use` + link hooks
- target minimal native binary under 1 MB where technically achievable
- README comparison vs hive_ce / isar_community / objectbox / drift
- package-quality hardening

### 0.9.0 — Hive Functional Parity Audit

- refresh the audit against the latest Hive CE release
- verify normal/lazy box workloads
- verify isolate and lifecycle semantics
- verify custom-object/schema-evolution replacement strategy
- verify encryption, compaction, watch/events, migration, and Web behavior
- add real Hive CE fixture migration tests
- close every practical capability marked `Gap`
- publish intentional API differences

See [`docs/HIVE_FUNCTIONAL_PARITY.md`](docs/HIVE_FUNCTIONAL_PARITY.md). **Any practical parity `Gap` blocks the 1.0 functional-replacement claim.**

### 1.0.0 — Stable

- Hive Functional Parity Audit passes with no practical `Gap`
- stable storage/API contract
- IndexedDB Web fallback
- pub.dev release

## License

MIT
