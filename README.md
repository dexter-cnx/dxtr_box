# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.1.x native foundation / active development**. Public API and storage format are not stable yet.

## Compatibility

Current minimum supported toolchain:

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

The minimum is verified in CI using Flutter 3.22.0 / Dart 3.4.0, while the normal CI lane continues to test the current stable Flutter toolchain. Minimum SDK increases are treated as explicit compatibility decisions rather than incidental dependency upgrades.

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
- Explicit plaintext -> encrypted migration with transactional recovery semantics.
- Native cross-handle `watch()` fan-out through FRB streams.
- Explicit native `deleteAll()` and `compact()` maintenance paths.
- Android, iOS, macOS, Linux, Windows first; Web fallback later.
- No `build_runner` for normal usage.
- Avoid loading an entire box into Dart RAM.
- Control native binary size without sacrificing the supported SDK floor.

Dart 3.13 recorded-use/native tree shaking is intentionally **future-only**. It must not raise the minimum SDK or become required for correctness. See [`docs/FUTURE_NATIVE_TREE_SHAKING.md`](docs/FUTURE_NATIVE_TREE_SHAKING.md).

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

An encrypted box must be reopened with the same key. Missing or incorrect keys are rejected. A plaintext box is never silently reinterpreted as encrypted. Existing plaintext boxes are converted only through the explicit maintenance API after all handles are closed:

```dart
final legacy = await DxtrBox.open('legacy');
await legacy.put('theme', 'dark');
await legacy.close();

await DxtrBox.encryptBox(
  'legacy',
  encryptionKey: 'correct horse battery staple',
);

final encrypted = await DxtrBox.open(
  'legacy',
  encryptionKey: 'correct horse battery staple',
);
```

The migration rewrites values and switches encryption metadata in one redb write transaction. Before the commit the durable box remains plaintext; after a successful return it is fully encrypted. Migration rejects live handles, empty keys, missing boxes, already-encrypted boxes, and unsupported storage formats.

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

### Native feature profiles

The default production native build remains `full` so current Flutter/Cargokit behavior does not change. Reduced profiles exist for intentional payload control and measurement:

| Profile | Cargo flags | Contract |
| --- | --- | --- |
| `minimal` | `--no-default-features` | CRUD + lifecycle + native watch |
| `encryption` | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| `full` | default features | encryption + maintenance (`compact`, plaintext -> encrypted migration) |

Native watch remains part of `minimal` because the current public `DxtrBox.open()` lifecycle registers a watcher before metadata hydration. Removing watch from the minimal profile would make the normal public Box lifecycle unusable.

The FRB symbol surface stays stable across profiles. If a reduced native build receives a call for functionality it does not contain, the operation fails explicitly rather than silently no-oping. In particular, `compact()` requires `maintenance`, and plaintext -> encrypted migration requires both `encryption` and `maintenance`.

PR #12 CI #144 validated the first same-run Linux x86_64 release-library baseline:

| Profile | Bytes | Delta vs minimal |
| --- | ---: | ---: |
| `minimal` | 1,893,736 | baseline |
| `encryption` | 1,992,296 | +98,560 (+5.2%) |
| `full` | 2,032,312 | +138,576 (+7.3%) |

These measurements are specific to that Linux x86_64 CI environment and are informational, not cross-platform package-size claims. CI retains only the `native-size-baseline.tsv` metadata artifact; Cargo target directories are not uploaded. No absolute size threshold is enforced until repeated controlled measurements are stable enough to justify a regression gate.

See [`docs/NATIVE_FEATURE_PROFILES.md`](docs/NATIVE_FEATURE_PROFILES.md) and [`docs/CARGO_FEATURE_SIZE_HANDOFF.md`](docs/CARGO_FEATURE_SIZE_HANDOFF.md).

### Encryption storage contract

Encrypted boxes persist metadata in a dedicated redb `meta` table:

- storage format marker: `dxtr_box/1`
- encryption mode: `none` or `chacha20poly1305`
- unique random salt per encrypted box
- encrypted key-check sentinel for early wrong-key rejection

Values are validated as MessagePack before storage, encrypted with a fresh random nonce per value, and authenticated by ChaCha20Poly1305. Reads decrypt and authenticate before returning bytes to Dart.

Legacy boxes without metadata are treated as known plaintext boxes and gain explicit plaintext metadata when normally reopened. Existing plaintext data is never encrypted implicitly.

## Developer workflow

The root `Makefile` is the preferred entry point:

```bash
make preflight
make native-test
make process-crash
make benchmark-smoke
make native-build-minimal
make native-build-encryption
make native-size-baseline
```

Additional targets cover FRB regeneration, Rust-only checks, a larger local benchmark run, and per-platform example builds.

## Engineering docs

- [Code walkthrough](docs/CODE_WALKTHROUGH.md) — Dart API -> codec -> FRB seam -> Rust API -> redb transaction, watch, encryption, deleteAll, compaction, migration, and native profile flow.
- [Testing strategy](docs/TESTING.md) — Dart/Rust test matrix, process-kill durability, benchmark methodology, local commands, profile matrix, and CI gates.
- [Native feature profiles](docs/NATIVE_FEATURE_PROFILES.md) — minimal/encryption/full Cargo contracts, measured Linux x86_64 baseline, and reduced-profile behavior.
- [Cargo feature + size handoff](docs/CARGO_FEATURE_SIZE_HANDOFF.md) — feature/profile design and binary-size baseline acceptance trail.
- [Plaintext -> encrypted migration](docs/PLAINTEXT_ENCRYPTION_MIGRATION.md) — explicit API, atomicity, lifecycle, and recovery contract.
- [Hive functional parity audit](docs/HIVE_FUNCTIONAL_PARITY.md) — 1.0 release gate for replacing practical Hive/Hive CE workloads.
- [Future native tree shaking](docs/FUTURE_NATIVE_TREE_SHAKING.md) — why Dart 3.13 native tree shaking is useful later, why it is deferred now, and the compatibility gate for revisiting it.
- [Project handoff](docs/PROJECT_HANDOFF.md) — current implementation status and milestone sequencing.
- [CI workflow](.github/workflows/ci.yml) — minimum-SDK compatibility, current Flutter analyze/test, native Linux round-trip + benchmark smoke, FRB drift detection, native profile matrix, and Linux size baseline capture.
- [Platform builds](.github/workflows/platform_builds.yml) — Android/iOS/macOS/Linux/Windows example compilation.

## Test suite

Current coverage includes:

- minimum-SDK pub get/analyze/tests on Flutter 3.22.0 / Dart 3.4.0.
- Dart dynamic codec round trips and invalid-map validation.
- `Box`/`DxtrBox` behavior through an in-memory native API fake.
- multi-handle lifecycle, concurrent close serialization, delete-while-open policy, base-path switching, and Windows-safe box-name validation.
- native cross-handle watch fan-out and watcher teardown semantics.
- real Dart -> FRB -> Rust -> redb Linux round-trip with close/reopen persistence.
- real encrypted Dart -> FRB -> Rust -> redb close/reopen round-trip with wrong/missing-key rejection.
- real public `DxtrBox.encryptBox()` -> FRB -> Rust plaintext-to-encrypted migration with live-handle rejection and post-migration data parity.
- transactional `deleteAll()` with exact removed-key event behavior.
- explicit redb-backed `compact()` lifecycle coverage.
- process-kill crash/reopen recovery for acknowledged plaintext and encrypted commits.
- a `hive_ce` benchmark smoke harness for equal logical workloads; timing is informational, not a CI pass/fail threshold.
- encryption tests for unique persisted salts, authenticated value round-trip, on-disk ciphertext, wrong keys, tampering, plaintext/encrypted mode mismatch, and migration failure safety.
- generated FRB binding drift detection in CI.
- minimal, encryption, and full Rust profile builds/tests on Ubuntu, macOS, and Windows.
- Linux x86_64 same-run native binary-size capture for all three profiles.
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
- explicit plaintext -> encrypted migration path
- process crash/reopen durability foundation
- Hive CE benchmark foundation
- developer Makefile

### 0.2.0 — Hive parity foundation

- Cargo feature splitting for optional functionality — implemented in PR #12
- retained benchmark result format and file-size reporting
- binary-size baselines for minimal CRUD, CRUD+encryption, and full feature builds — first Linux x86_64 baseline implemented in PR #12

### 0.3.0 — Query & migration

- whereEquals / whereGreaterThan
- sortBy / limit
- secondary indexes
- migrateFromHiveCe

### 0.4.0 — Production hardening

- binary-size regression checks after repeated baseline validation
- package-quality hardening
- comparison vs hive_ce / isar_community / objectbox / drift

Dart 3.13 native tree shaking is **not assigned to the active roadmap**. Revisit it only after the conditions in `docs/FUTURE_NATIVE_TREE_SHAKING.md` are satisfied.

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
