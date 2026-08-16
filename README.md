# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.4 Production Hardening active**. PH-01 native-size policy and PH-02 package hardening are complete; PH-03 broader local-database comparison is active. The package preview is `0.4.0-dev.1`; no pub.dev release is performed by the hardening PRs. Public API and storage format are not stable yet.

## Compatibility

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

The minimum is verified in CI using Flutter 3.22.0 / Dart 3.4.0.

## Package architecture

`dxtr_box` is a self-contained Flutter FFI plugin. Consumer-required native inputs live in the same package:

```text
lib/        Dart API + generated FRB bindings
rust/       Rust crate (native library: rust_lib_dxtr_box)
cargokit/   Rust/native build integration
android/
ios/
macos/
linux/
windows/
example/
```

The Flutter package/plugin identity is `dxtr_box`; the Rust crate/library intentionally remains `rust_lib_dxtr_box` to preserve the existing FRB/native loading contract. There is no nested path-dependent native builder package.

## Why

`dxtr_box` targets Hive-like ergonomics while moving persistence, transactions, encryption, maintenance, query execution, and native event fan-out into Rust. Values are not retained wholesale in the Dart heap just to imitate Hive's synchronous read model.

Design goals include:

- Hive-simple asynchronous API;
- functional replacement for practical Hive/Hive CE local-database workloads by 1.0;
- `redb` ACID storage, one `{box}.dxtr` file per box;
- Flutter Rust Bridge v2 boundary;
- MessagePack dynamic values;
- Argon2 + ChaCha20Poly1305 encryption;
- explicit plaintext-to-encrypted and Hive CE migration;
- native cross-handle `watch()` fan-out;
- declarative native queries and persisted indexes;
- Android, iOS, macOS, Linux, Windows first; Web later;
- no model `build_runner` requirement;
- bounded native-size regression policy without weakening correctness.

Dart 3.13 recorded-use/native tree shaking remains future-only and must not raise the current SDK floor.

## Basic API

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');

await box.put('theme', 'dark');
final theme = await box.get('theme');

await box.deleteAll(['theme', 'legacy']);
await box.compact();
await box.close();
```

Native reads are asynchronous because they may perform real storage I/O.

## Encryption

```dart
final secure = await DxtrBox.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);

await secure.put('token', 'secret');
await secure.close();
```

Encrypted boxes require the same key on reopen. Plaintext-to-encrypted conversion is explicit and transactional.

## Hive CE migration

Core `dxtr_box` has no runtime dependency on Hive CE. Applications open the source using Hive CE itself and wrap it:

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

Migration preflights converted values, detects converted-key collisions, preserves source data, and writes through one destination `putAll` transaction. A distinct reservation marker prevents concurrent migrations and prevents ordinary `DxtrBox.open(destinationName)` from returning a usable handle while migration owns the target.

Real Hive CE 2.19.3 fixtures are isolated under `tool/hive_ce_migration_fixture/` so they do not raise the root Dart/Flutter minimum. See `docs/HIVE_CE_MIGRATION_03.md`.

## Declarative queries

```dart
final rows = await box.query(
  BoxQuery(
    where: QueryGroup.and([
      QueryComparison(
        field: 'profile.age',
        operator: QueryOperator.greaterThanOrEqual,
        value: 18,
      ),
      QueryComparison(
        field: 'status',
        operator: QueryOperator.equal,
        value: 'active',
      ),
    ]),
    sortBy: const [
      QuerySort(
        field: 'profile.age',
        direction: QuerySortDirection.descending,
        nulls: QueryNullOrder.last,
      ),
    ],
    limit: 20,
  ),
);
```

Current query guarantees:

- one FRB call per declarative query;
- dotted nested fields;
- equality/inequality, ordered comparisons, `between`, null checks, AND/OR;
- exact signed/unsigned integer semantics;
- deterministic semantic sorting before pagination;
- record-key ascending final tie-break;
- one redb read snapshot for planner, primary reads, and sort inputs;
- plaintext/encrypted scans;
- persisted scalar index narrowing for `equal`, `>`, `>=`, `<`, `<=`, and `between` under `full`;
- multi-index candidate intersection under AND;
- authoritative primary-record re-read and full predicate re-evaluation.

Persisted indexes narrow `where` candidates only; they do not currently satisfy ORDER BY. Raw MessagePack bytes are not treated as numeric order.

## Persisted indexes

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-age', field: 'profile.age'),
);

final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-age');
```

Primary data is authoritative. Index definitions and entries are derived state maintained in the same redb write transaction as primary mutations. Encrypted boxes intentionally reject persisted index creation until a non-leaking representation is designed.

## Native feature profiles

Exactly three Rust capability profiles are supported:

| Profile | Cargo flags | Contract |
| --- | --- | --- |
| `minimal` | `--no-default-features` | CRUD + lifecycle + native watch |
| `encryption` | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| `full` | default | encryption + maintenance + query/index implementation |

`full` remains the default production build. Do not add a fourth product profile merely for binary-size tuning.

## Native-size hardening

0.4 adds a controlled cross-commit gate. Base and head commits are built from committed snapshots on the same Linux x64 runner/toolchain and compared independently for all three profiles.

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
```

The budget is a regression alarm, not routine allowance. See `docs/NATIVE_SIZE_POLICY_04.md`.

## Package / pub.dev readiness

The package is validated as a self-contained archive before any future publication:

```bash
make package-readiness
```

This runs public API documentation generation and `dart pub publish --dry-run`. CI also checks that consumer-required Rust/Cargokit/platform files are present and that no publishable dependency uses a path source. The five-platform example build workflow remains mandatory because a successful pub dry-run does not prove native builds.

`flutter_rust_bridge` remains pinned to 2.8.0 because checked-in generated bindings and native runtime must remain on the same FRB version; the pub dry-run therefore ignores the advisory broad-dependency warning while still failing validation errors.

No package is automatically published by CI or by PH-02. See `docs/PACKAGE_RELEASE_04.md`.

## Local database comparison

PH-03 broadens benchmark evidence beyond Hive CE. The current matrix runs `dxtr_box`, Hive CE, Sembast, and SQLite through `sqflite_common_ffi`.

Correctness and timing are intentionally separate:

```bash
make benchmark-comparison-correctness
make benchmark-comparison
```

The correctness gate verifies a shared CRUD/overwrite/delete/close/reopen workload converges to the same persisted snapshot across all four engines. The diagnostic matrix measures sequential put, batch put, point get, contains, delete-all, and reopen-read, but **does not assert that any engine must be faster than another**.

CI uploads machine-readable JSONL evidence as the `local-database-comparison` artifact. Hosted-runner timing is diagnostic only and must not be presented as stable product performance. See `docs/LOCAL_DATABASE_COMPARISON_04.md`.

## Developer workflow

Common root targets:

```bash
make preflight
make package-readiness
make dart-doc
make pub-dry-run
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make process-crash
make benchmark-smoke
make benchmark-comparison-correctness
make benchmark-comparison
make benchmark-query-index
make diagnose-point-read
make rust-check
make native-size-baseline
make native-size-stability
make native-size-regression
```

Platform examples:

```bash
make example-android
make example-ios
make example-macos
make example-linux
make example-windows
```

## Engineering docs

- `docs/PROJECT_HANDOFF.md` — current milestone state and sequencing.
- `docs/CODE_WALKTHROUGH.md` — Dart -> FRB -> Rust -> redb architecture.
- `docs/PACKAGE_RELEASE_04.md` — self-contained plugin and publication-readiness contract.
- `docs/NATIVE_SIZE_POLICY_04.md` — controlled native-size regression policy.
- `docs/LOCAL_DATABASE_COMPARISON_04.md` — PH-03 correctness + diagnostic comparison contract.
- `docs/QUERY_INDEX_03.md` — query/index semantics and planner constraints.
- `docs/HIVE_CE_MIGRATION_03.md` — Hive CE migration contract and failure behavior.
- `docs/HIVE_FUNCTIONAL_PARITY.md` — 1.0 Hive/Hive CE functional-parity release gate.

## 1.0 direction

A 1.0 release requires practical Hive/Hive CE functional parity, a stable storage/API contract, and a completed Web/IndexedDB strategy. The current 0.4 work is production/package hardening, not a stable-API claim.
