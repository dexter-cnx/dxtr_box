# dxtr_box

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.1.0 foundation / active development**. Public API and storage format are not stable yet.

## Why

Hive's original project is no longer a suitable foundation for new production work, while Dart-only box databases generally keep their hot data in Dart memory. `dxtr_box` targets Hive-like ergonomics while moving persistence, transactions, and heavy work into Rust.

## Design goals

- Hive-simple API.
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

## Roadmap

### 0.1.0 — MVP

- init / open
- put / get / delete / clear
- length / keys / values
- Android / iOS / macOS / Linux / Windows
- FRB code generation
- Rust + Flutter tests

### 0.2.0 — Hive parity

- putAll / deleteAll
- deleteBox / boxExists
- encryption
- native `watch()` stream
- compact
- benchmark against `hive_ce`
- Cargo feature splitting for optional functionality

### 0.3.0 — Query engine

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

### 1.0.0

- stable storage/API contract
- IndexedDB Web fallback
- pub.dev release

See [`docs/PROJECT_HANDOFF.md`](docs/PROJECT_HANDOFF.md) for engineering status and sequencing.

## License

MIT
