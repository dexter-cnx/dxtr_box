# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**Native local database for Flutter, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered local database for Flutter. No model code generation.

> Status: **0.6 Query / Index + Encryption Hardening is complete when PR #43 merges with the full quality bar green.** The milestone established an explicit encrypted-index threat model, added persisted encrypted equality indexes using domain-separated keyed BLAKE2b tokens, and intentionally retained authoritative scan-backed execution for encrypted ordered/range predicates. The next planned milestone is **0.7 Query Ergonomics**, an additive fluent Dart API over the existing `BoxQuery` AST. Dxtr_Box is not positioned as a Hive/Hive CE replacement; Hive CE remains an optional migration source, compatibility reference, and benchmark peer. The package remains pre-1.0; public API and storage format are not declared stable.

## Key Features

- **Rust/redb ACID storage** — durable native persistence outside the Dart heap.
- **Simple box-style Flutter API** — asynchronous CRUD without application model code generation.
- **Fast authoritative reads** — optimized point reads plus one-snapshot `getAll` multi-key reads.
- **Declarative native queries** — nested field comparisons, boolean groups, pagination, and deterministic sorting.
- **Persisted secondary indexes** — equality/range candidate narrowing for plaintext boxes plus equality-only encrypted narrowing under `full`.
- **First-class encryption** — Argon2 key derivation + ChaCha20Poly1305 authenticated encryption.
- **Encrypted equality tokens** — domain-separated deterministic keyed BLAKE2b MAC tokens; plaintext scalar bytes are not persisted in encrypted index entries.
- **Transactional bulk operations** — primary records and derived index maintenance commit atomically.
- **Native watch events** — cross-handle change notifications through Flutter Rust Bridge streams.
- **Crash/reopen durability coverage** — acknowledged writes are validated across reopen/crash scenarios.
- **Migration tooling** — explicit plaintext-to-encrypted conversion and optional Hive CE migration support.
- **Five native platforms** — Android, iOS, macOS, Linux, and Windows consumer validation.
- **Self-contained Flutter FFI plugin** — Rust/Cargokit/native platform inputs ship with the package.

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

`dxtr_box` is designed as a native local database for Flutter rather than an in-memory-first Dart store. Persistence, transactions, encryption, maintenance, query execution, and native event fan-out live in Rust/redb, while Dart provides the public developer-facing API and value codec.

Design goals include:

- simple asynchronous Flutter ergonomics;
- `redb` ACID storage, one `{box}.dxtr` file per box;
- Flutter Rust Bridge v2 boundary;
- MessagePack dynamic values;
- Argon2 + ChaCha20Poly1305 encryption;
- explicit plaintext-to-encrypted migration;
- optional Hive CE migration/interoperability tooling;
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

final selected = await box.getAll(['theme', 'missing', 'theme']);
// Hits preserve requested order, missing keys are omitted,
// and duplicate requested keys produce duplicate result entries.

await box.deleteAll(['theme', 'legacy']);
await box.compact();
await box.close();
```

Native reads remain asynchronous at the public Dart API. Internally, only the tiny single-key Rust `get` and `contains_key` FRB entrypoints use synchronous generated dispatch; batch reads, queries, mutations, scans, and migrations remain asynchronous. `getAll` uses one native crossing and one short-lived redb read snapshot for the requested key set.

## Encryption

```dart
final secure = await DxtrBox.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);

await secure.put('token', 'secret');
await secure.close();
```

Encrypted boxes require the same key on reopen. Plaintext-to-encrypted conversion is explicit and transactional. Encrypted point, batch, query, and encrypted-index candidate reads retain full AEAD authentication.

## Hive CE migration

Hive CE support is optional interoperability tooling, not the product identity or API target. Core `dxtr_box` has no runtime dependency on Hive CE. Applications open the source using Hive CE itself and wrap it:

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
- plaintext persisted scalar index narrowing for `equal`, `>`, `>=`, `<`, `<=`, and `between` under `full`;
- encrypted persisted index narrowing for `equal` under `full`;
- encrypted ordered/range predicates remain scan-backed;
- multi-index candidate intersection under AND where usable candidates exist;
- authoritative primary-record re-read and full predicate re-evaluation.

Persisted indexes narrow `where` candidates only; they do not currently satisfy ORDER BY. Raw MessagePack bytes are not treated as numeric order.

The planned 0.7 Query Ergonomics milestone will add fluent Dart syntax that compiles into this same `BoxQuery` AST rather than introducing a second query engine. See `docs/QUERY_ERGONOMICS_07.md`.

## Persisted indexes

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-age', field: 'profile.age'),
);

final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-age');
```

Primary data is authoritative. Index definitions and entries are derived state maintained in the same redb write transaction as primary mutations.

For plaintext boxes, persisted scalar indexes support equality and ordered/range narrowing. For encrypted boxes, persisted indexes use deterministic 256-bit BLAKE2b keyed MAC tokens for **equality narrowing only**. Tokens are derived from authenticated box key material and domain-separated by index name and field. Raw plaintext scalar values are not persisted in encrypted index entries.

Encrypted equality indexing intentionally leaks equality classes/frequency for repeated indexed values, and index metadata still exposes index/field names plus record identifiers. Every candidate is still resolved through the authoritative encrypted primary record, ChaCha20Poly1305 authenticated/decrypted, and fully predicate-rechecked before it can be returned. Encrypted range operators do not treat keyed tokens as order-preserving and continue to use authoritative scan fallback. See `docs/QUERY_INDEX_ENCRYPTION_06.md`.

Plaintext-to-encrypted migration still requires persisted plaintext indexes to be dropped before migration; recreate them after opening the encrypted box so derived state is generated using the encrypted equality-index contract.

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

PR2's encrypted equality-index implementation reuses BLAKE2 already present through Argon2 rather than adding a second heavy hash dependency. The validated Linux x64 full-profile artifact moved from 2,385,720 to 2,416,152 bytes: +30,432 bytes / +1.276%, within policy.

The budget is a regression alarm, not routine allowance. See `docs/NATIVE_SIZE_POLICY_04.md`.

## Package / pub.dev readiness

The package is validated before any future publication:

```bash
make package-readiness
```

This runs public API documentation generation and `dart pub publish --dry-run --ignore-warnings`. CI also checks that consumer-required Rust/Cargokit/platform files are present and that no publishable dependency uses a path source.

`flutter_rust_bridge` remains pinned to 2.8.0 because checked-in generated bindings and native runtime must remain on the same FRB version; the pub dry-run therefore ignores the advisory broad-dependency warning while still failing validation errors.

No package is automatically published by CI or by the hardening/performance milestones. See `docs/PACKAGE_RELEASE_04.md`.

## Published-payload consumer validation

PH-04 adds a stronger native package-boundary proof. `tool/validate_published_consumer.dart` stages the files allowed by the current `.pubignore`, verifies required native inputs and absence of repository-only leakage, creates a fresh Flutter app, adds only the staged `dxtr_box` copy as a dependency, imports the public API, and builds the app.

The main CI DAG validates all five native targets before merge when consumer/native behavior can be affected:

```bash
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

During Draft iteration, platform-specific changes can validate only the affected platform after Fast CI; common native/plugin/package changes still fan out as required. The staging helper fails closed if `.pubignore` starts using wildcard/negation rules it does not model exactly. `dart pub publish --dry-run` remains the source of truth for pub validation and intended file listing. See `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md` and `docs/CI_STRATEGY.md`.

## Public API + durable storage contract guard

PH-05 adds fail-fast compatibility change control without claiming pre-1.0 stability.

```bash
dart run tool/verify_public_storage_contract.dart
```

The normal Flutter test suite also runs this contract. It verifies the package entrypoint export set, compiles representative public constructors/enums/typedefs and typed `Box`/`DxtrBox`/migration signatures, and guards the current durable metadata identity:

```text
meta key: format_version
value:    dxtr_box/1
```

A deliberate 0.x API change is allowed only with an intentional contract/doc update. A future storage-format change must include backward-read or migration behavior plus compatibility evidence rather than merely updating the marker. PH-05 completed in PR #31. See `docs/PUBLIC_API_STORAGE_CONTRACT_04.md`.

## Local database comparison

PH-03 broadens benchmark evidence beyond a single peer. The current matrix runs `dxtr_box`, Hive CE, Sembast, and SQLite through `sqflite_common_ffi`.

Correctness and timing are intentionally separate:

```bash
make benchmark-comparison-correctness
make benchmark-comparison
```

The correctness gate verifies a shared CRUD/overwrite/delete/close/reopen workload converges to the same persisted snapshot across all four engines. The diagnostic matrix measures sequential put, batch put, point get, contains, delete-all, and reopen-read, but **does not assert that any engine must be faster than another**.

`Box.getAll` is intentionally not forced into that four-engine matrix because the other adapters do not expose an equivalent contract with identical order/missing/duplicate semantics. Its evidence comes from the dedicated dxtr_box batch benchmark instead.

CI uploads machine-readable JSONL evidence as the `local-database-comparison` artifact. Hosted-runner timing is diagnostic only and must not be presented as stable product performance. See `docs/LOCAL_DATABASE_COMPARISON_04.md` and `docs/PERFORMANCE_05_CLOSURE_AUDIT.md`.

## Query/index diagnostic benchmark

Use the dedicated matrix for query/index engineering evidence:

```bash
make benchmark-query-index
```

The harness covers plaintext scan/index equality, range, AND intersection, and sorted-range scenarios plus encrypted equality scan versus encrypted equality-index narrowing. Timing is diagnostic only; correctness, authenticated primary recheck, durability, and the encrypted-index security contract are the hard gates.

## Fast local preflight

Run this before pushing:

```bash
make preflight
```

It mirrors the mandatory Fast CI gate and catches common cheap failures first: Dart formatting, rustfmt, Flutter analyze, Rust clippy, compile checks for `minimal`/`encryption`/`full`, cheap Dart/Rust tests, and public/storage contract guards.

Individual targets are also available:

```bash
make format-check
make rust-check
make analyze
make test-fast
make ci-fast
```

Expensive migration/native-size/FRB/publication/platform/benchmark validation remains change-aware during Draft iteration and becomes mandatory full validation when a pull request is Ready for review. See `docs/CI_STRATEGY.md`.

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
make benchmark-read-path
make benchmark-batch-read
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
- `docs/CODE_WALKTHROUGH.md` — Dart -> FRB -> Rust -> redb architecture and CI DAG.
- `docs/QUERY_INDEX_ENCRYPTION_06.md` — completed 0.6 encrypted-index threat model and runtime/security contract.
- `docs/ENCRYPTED_RANGE_DECISION_06.md` — rationale for scan-backed encrypted ordered/range predicates.
- `docs/RELEASE_AUDIT_06.md` — final 0.6 acceptance/closure matrix.
- `docs/QUERY_ERGONOMICS_07.md` — planned additive fluent-query milestone over the existing `BoxQuery` AST.
- `docs/PERFORMANCE_READ_PATH_05.md` — 0.5 read-path measurements and production decisions.
- `docs/READ_SESSION_INVESTIGATION_05.md` — evidence-backed read-session decision.
- `docs/PERFORMANCE_05_CLOSURE_AUDIT.md` — final 0.5 acceptance audit.
- `docs/CI_STRATEGY.md` — Fast CI, affected CI, full merge validation, and trigger policy.
- `docs/PACKAGE_RELEASE_04.md` — self-contained plugin and publication-readiness contract.
- `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md` — PH-04 staged publication-boundary consumer build contract.
- `docs/PUBLIC_API_STORAGE_CONTRACT_04.md` — PH-05 public API and durable-format change-control contract.
- `docs/NATIVE_SIZE_POLICY_04.md` — controlled native-size regression policy.
- `docs/LOCAL_DATABASE_COMPARISON_04.md` — PH-03 correctness + diagnostic comparison contract.
- `docs/QUERY_INDEX_03.md` — query/index semantics and planner constraints.
- `docs/HIVE_CE_MIGRATION_03.md` — optional Hive CE migration contract and failure behavior.
- `docs/HIVE_FUNCTIONAL_PARITY.md` — historical compatibility inventory only; not the product direction or a 1.0 release gate.

## 1.0 direction

A 1.0 release should represent a coherent, production-ready native local database contract: durable storage, simple public API, query/index behavior, encryption semantics, migration compatibility, and five-platform packaging. It is not defined by Hive/Hive CE feature parity.
