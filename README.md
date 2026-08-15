# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.1.x native foundation / active development**. Public API and storage format are not stable yet.

## Why

`dxtr_box` targets Hive-like ergonomics while moving persistence, transactions, encryption, maintenance, and native event fan-out into Rust. Values are not retained wholesale in the Dart heap just to imitate Hive's synchronous read model.

## Design goals

- Hive-simple API.
- Functional replacement for practical Hive/Hive CE local-database workloads by 1.0.
- `redb` ACID storage engine.
- One file per box: `{base_path}/{box_name}.dxtr`.
- Thin Dart wrapper over Rust through Flutter Rust Bridge v2.
- MessagePack value encoding.
- Per-box encryption with Argon2 + ChaCha20Poly1305.
- Native cross-handle `watch()` fan-out through FRB streams.
- Explicit native `deleteAll()` and `compact()` maintenance paths.
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

await box.deleteAll(['theme', 'legacy']);
await box.compact();
await box.close();
```

Encrypted boxes use the same API with an `encryptionKey`:

```dart
final secure = await DxtrBox.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);

await secure.put('token', 'secret');
await secure.close();
```

An encrypted box must be reopened with the same key. Missing or incorrect keys are rejected. A plaintext box is never silently reinterpreted as encrypted; explicit migration will be required for that transition.

Native reads are asynchronous by design: unlike Hive's in-memory read model, `dxtr_box` may perform real storage I/O and should not block Flutter's UI isolate.

Values are fetched from native storage on demand rather than cached wholesale in Dart. Hive-style `lazy: true` semantics are not implemented yet, so `DxtrBox.open(..., lazy: true)` currently throws `UnsupportedError` instead of pretending to support a distinct lazy mode.

## Engine

- Rust
- `redb = 2.1`
- `flutter_rust_bridge = 2.8`
- `rmp-serde`
- `once_cell` + `parking_lot`
- `argon2`
- `chacha20poly1305`

Native build ownership lives in the checked-in `rust_builder/` Cargokit plugin. The root package is the Dart-facing facade and intentionally has no duplicate platform plugin scaffolds.

### Encryption storage contract

Encrypted boxes persist metadata in a dedicated redb `meta` table:

- storage format marker: `dxtr_box/1`
- encryption mode: `none` or `chacha20poly1305`
- unique random 16-byte salt per encrypted box
- encrypted key-check sentinel for early wrong-key rejection

Values are validated as MessagePack before storage, encrypted with a fresh random nonce per value, and authenticated by ChaCha20Poly1305. Reads decrypt and authenticate before returning bytes to Dart.

Legacy boxes without metadata are treated as known plaintext boxes and gain explicit plaintext metadata when normally reopened. Existing plaintext data is never encrypted in place implicitly.

## Developer workflow

The root `Makefile` is the preferred entry point:

```bash
make preflight
make native-test
make process-crash
make benchmark-smoke
```

Additional targets cover FRB regeneration, Rust-only checks, a larger local benchmark run, and per-platform example builds.

## Engineering docs

- [Code walkthrough](docs/CODE_WALKTHROUGH.md) — Dart API -> codec -> FRB seam -> Rust API -> redb transaction, watch, encryption, deleteAll, and compaction flow.
- [Testing strategy](docs/TESTING.md) — Dart/Rust test matrix, process-kill durability, benchmark methodology, local commands, and CI gates.
- [Hive functional parity audit](docs/HIVE_FUNCTIONAL_PARITY.md) — 1.0 release gate for replacing practical Hive/Hive CE workloads.
- [Project handoff](docs/PROJECT_HANDOFF.md) — current implementation status and milestone sequencing.
- [CI workflow](.github/workflows/ci.yml) — Flutter analyze/test, native Linux round-trip + benchmark smoke, and Rust host-matrix checks.
- [Platform builds](.github/workflows/platform_builds.yml) — Android/iOS/macOS/Linux/Windows example compilation.

## Test suite

Current coverage includes:

- Dart dynamic codec round trips and invalid-map validation.
- `Box`/`DxtrBox` behavior through an in-memory native API fake.
- multi-handle lifecycle, concurrent close serialization, delete-while-open policy, base-path switching, and Windows-safe box-name validation.
- native cross-handle watch fan-out and watcher teardown semantics.
- real Dart -> FRB -> Rust -> redb Linux round-trip with close/reopen persistence.
- real encrypted Dart -> FRB -> Rust -> redb close/reopen round-trip with wrong/missing-key rejection.
- transactional `deleteAll()` with exact removed-key event behavior.
- explicit redb-backed `compact()` lifecycle coverage.
- process-kill crash/reopen recovery for acknowledged plaintext and encrypted commits.
- a `hive_ce` benchmark smoke harness for equal logical workloads; timing is informational, not a CI pass/fail threshold.
- encryption tests for unique persisted salts, authenticated value round-trip, on-disk ciphertext, wrong keys, tampering, and plaintext/encrypted mode mismatch.
- Rust fmt/clippy/tests on Ubuntu, macOS, and Windows.
- example compilation on Android, iOS without code signing, macOS, Linux, and Windows.

## Roadmap

### 0.1.x — Native foundation

- init / open
- put / get / delete / clear
- putAll / deleteAll
- compact
- length / keys / values
- deleteBox / boxExists
- Android / iOS / macOS / Linux / Windows
- FRB code generation + Cargokit integration
- lifecycle and multi-handle hardening
- native `watch()` stream
- persisted per-box encryption metadata + encrypted value path
- developer Makefile

### 0.2.0 — Hive parity foundation

- process-level crash/reopen durability tests
- reproducible benchmark against `hive_ce`
- benchmark file-size reporting and retained result format
- explicit plaintext -> encrypted migration path
- Cargo feature splitting for optional functionality

### 0.3.0 — Query & migration

- whereEquals / whereGreaterThan
- sortBy / limit
- secondary indexes
- migrateFromHiveCe

### 0.4.0 — Production hardening

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
