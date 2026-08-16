# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.4 Production Hardening active**. PH-01 native-size policy, PH-02 package hardening, PH-03 broader local-database comparison, and PH-04 staged published-payload consumer validation are complete. PH-05 public API + durable storage contract guarding is active. The package preview is `0.4.0-dev.1`; no pub.dev release is performed by the hardening PRs. Public API and storage format are still pre-1.0 and not declared stable.

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

The package is validated before any future publication:

```bash
make package-readiness
```

This runs public API documentation generation and `dart pub publish --dry-run --ignore-warnings`. CI also checks that consumer-required Rust/Cargokit/platform files are present and that no publishable dependency uses a path source.

`flutter_rust_bridge` remains pinned to 2.8.0 because checked-in generated bindings and native runtime must remain on the same FRB version; the pub dry-run therefore ignores the advisory broad-dependency warning while still failing validation errors.

No package is automatically published by CI or by the hardening milestones. See `docs/PACKAGE_RELEASE_04.md`.

## Published-payload consumer validation

PH-04 adds a stronger native package-boundary proof. `tool/validate_published_consumer.dart` stages the files allowed by the current `.pubignore`, verifies required native inputs and absence of repository-only leakage, creates a fresh Flutter app, adds only the staged `dxtr_box` copy as a dependency, imports the public API, and builds the app.

Platform Builds run this staged-consumer flow for all five native targets:

```bash
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

The staging helper fails closed if `.pubignore` starts using wildcard/negation rules it does not model exactly. `dart pub publish --dry-run` remains the source of truth for pub validation and intended file listing; the staged consumer gate is complementary build evidence. PH-04 completed in PR #30. See `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md`.

## Public API + durable storage contract guard

PH-05 adds fail-fast compatibility change control without claiming pre-1.0 stability.

```bash
dart run tool/verify_public_storage_contract.dart
```

The normal Flutter test suite also runs this contract. It verifies the package entrypoint export set, compiles representative public constructors/enums/typedefs and typed `Box` method/getter signatures, and guards the current durable metadata identity:

```text
meta key: format_version
value:    dxtr_box/1
```

A deliberate 0.x API change is allowed only with an intentional contract/doc update. A future storage-format change must include backward-read or migration behavior plus compatibility evidence rather than merely updating the marker. See `docs/PUBLIC_API_STORAGE_CONTRACT_04.md`.

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
dart run tool/verify_public_storage_contract.dart
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
make published-consumer-linux
```

The original example build targets remain available for local documentation/example validation:

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
- `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md` — PH-04 staged publication-boundary consumer build contract.
- `docs/PUBLIC_API_STORAGE_CONTRACT_04.md` — PH-05 public API and durable-format change-control contract.
- `docs/NATIVE_SIZE_POLICY_04.md` — controlled native-size regression policy.
- `docs/LOCAL_DATABASE_COMPARISON_04.md` — PH-03 correctness + diagnostic comparison contract.
- `docs/QUERY_INDEX_03.md` — query/index semantics and planner constraints.
- `docs/HIVE_CE_MIGRATION_03.md` — Hive CE migration contract and failure behavior.
- `docs/HIVE_FUNCTIONAL_PARITY.md` — 1.0 Hive/Hive CE functional-parity release gate.

## 1.0 direction

A 1.0 release requires practical Hive/Hive CE functional parity, a stable storage/API contract, and a completed Web/IndexedDB strategy. The current 0.4 work is production/package hardening, not a stable-API claim.
