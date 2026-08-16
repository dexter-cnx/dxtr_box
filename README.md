# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**The Hive replacement, forged in Rust. By Dxtr.**

A fast, ACID, encrypted, Rust-powered NoSQL box database for Flutter. No model code generation.

> Status: **0.3 query/index planner / active development**. Public API and storage format are not stable yet.

## Compatibility

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

The minimum is verified in CI using Flutter 3.22.0 / Dart 3.4.0. Minimum SDK increases are explicit compatibility decisions rather than incidental dependency upgrades.

## Why

`dxtr_box` targets Hive-like ergonomics while moving persistence, transactions, encryption, maintenance, query execution, and native event fan-out into Rust. Values are not retained wholesale in the Dart heap just to imitate Hive's synchronous read model.

## Design goals

- Hive-simple API.
- Functional replacement for practical Hive/Hive CE local-database workloads by 1.0.
- `redb` ACID storage engine.
- One file per box: `{base_path}/{box_name}.dxtr`.
- Thin Dart wrapper over Rust through Flutter Rust Bridge v2.
- MessagePack dynamic value encoding.
- Per-box encryption with Argon2 + ChaCha20Poly1305.
- Explicit transactional plaintext -> encrypted migration.
- Native cross-handle `watch()` fan-out.
- Declarative native query execution with one FRB call per query.
- Persisted secondary indexes with transactional maintenance and conservative index-backed planning.
- Android, iOS, macOS, Linux, Windows first; Web fallback later.
- No `build_runner` for normal usage.
- Avoid loading an entire box into Dart RAM.
- Control native binary size without sacrificing the supported SDK floor.

Dart 3.13 recorded-use/native tree shaking is intentionally future-only. It must not raise the minimum SDK or become required for correctness. See [`docs/FUTURE_NATIVE_TREE_SHAKING.md`](docs/FUTURE_NATIVE_TREE_SHAKING.md).

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

Native reads are asynchronous by design because they may perform real storage I/O.

## Encryption

```dart
final secure = await DxtrBox.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);

await secure.put('token', 'secret');
await secure.close();
```

Encrypted boxes require the same key on reopen. Plaintext boxes are never silently reinterpreted as encrypted. Plaintext-to-encrypted migration is explicit and transactional.

## Declarative query API

The 0.3 query engine uses a structured AST rather than executing one Dart predicate callback per stored value.

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
    limit: 20,
  ),
);
```

Current native query behavior:

- one FRB call per query;
- dotted field paths such as `profile.age`;
- equality/inequality, ordering, `between`, and null checks;
- AND/OR groups;
- exact integer comparisons without collapsing large MessagePack integers through `f64`;
- deterministic record-key ordering before offset/limit;
- plaintext and encrypted native scans;
- full-profile planner can narrow candidates through matching persisted scalar indexes for `equal`, `>`, `>=`, `<`, `<=`, and `between`;
- multiple usable persisted indexes under an AND group may be intersected;
- every candidate is still re-read and re-evaluated from primary data;
- planner lookup, fallback key enumeration, and primary-record reads share one redb read transaction snapshot per native query.

Legacy `Box.where(predicate)` remains available as a Dart-side linear scan, separate from the declarative native engine.

## Persisted secondary indexes

```dart
await box.createIndex(
  const IndexDefinition(
    name: 'by-age',
    field: 'profile.age',
  ),
);

final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-age');
```

Persisted index definitions and entries live in redb and are maintained in the same write transaction as primary record mutations.

Planner eligibility applies at the top level or recursively beneath `AND` groups when an index exists for the exact field. The planner deliberately does not narrow through `OR` groups. `notEqual`, `isNull`, and `isNotNull` remain scan-backed.

For AND queries with several usable indexes, candidate key sets are intersected starting from the smallest set. The full original predicate is then re-evaluated against primary data before deterministic ordering and pagination. Candidate planning, fallback enumeration, and primary reads all use the same redb `ReadTransaction`, giving each native query a single consistent storage snapshot.

Range planning is correctness-first. Persisted scalar components use MessagePack encoding, whose raw lexicographic byte order is not a general numeric order. Therefore current range matching decodes indexed scalar components and applies the same exact comparator as the query engine instead of treating MessagePack bytes as redb numeric range bounds. A faster range seek requires an order-preserving scalar encoding or equivalent proven ordering contract.

Integration coverage compares scan results with indexed execution for equality, nested `profile.age` ranges (`>`, `>=`, `<`, `<=`), inclusive `between`, and multi-index AND intersection.

Encrypted boxes can use native scan queries, but persisted index creation is intentionally rejected until a non-leaking encrypted-index representation is designed. Plaintext-to-encrypted migration is rejected while persisted index definitions exist. Reduced native profiles reject opening boxes that already contain persisted index definitions.

See [`docs/QUERY_INDEX_03.md`](docs/QUERY_INDEX_03.md).

## Engine

- Rust
- `redb = 2.1`
- `flutter_rust_bridge = 2.8`
- `rmp-serde`
- `rmpv` in the full query/index profile
- `once_cell` + `parking_lot`
- `argon2`
- `chacha20poly1305`

Native build ownership lives in the checked-in `rust_builder/` Cargokit package.

## Native feature profiles

There are exactly three public native product profiles:

| Profile | Cargo flags | Contract |
| --- | --- | --- |
| `minimal` | `--no-default-features` | CRUD + lifecycle + native watch |
| `encryption` | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| `full` | default features | encryption + maintenance + query/index implementation |

`full` remains the default production build. Do not add a fourth public query profile.

Reduced profiles retain the stable FRB surface and fail explicitly when a requested operation requires a capability not compiled into that profile. Boxes containing persisted indexes require `full` for safe mutation.

PR #12 established the first Linux x86_64 native profile baseline. PR #13 verified zero-byte spread across repeated same-commit builds for each profile. This remains a same-commit reproducibility gate, not a cross-commit size budget.

## Storage/encryption contract

Core redb tables:

```text
data
meta
```

Full-profile query/index adds:

```text
index_definitions
index_entries
```

Primary `data` is authoritative. Indexes are derived state.

Encrypted boxes persist a format marker, encryption mode, unique salt, and encrypted key-check sentinel. Record keys are used as AAD.

## Developer workflow

The root `Makefile` is the preferred entry point:

```bash
make preflight
make native-test
make query-index-test
make process-crash
make benchmark-smoke
make native-build-minimal
make native-build-encryption
make native-size-baseline
make native-size-stability
```

Additional targets cover FRB regeneration, larger local benchmarks, Rust-only checks, and per-platform example builds.

## Engineering docs

- [Code walkthrough](docs/CODE_WALKTHROUGH.md) — Dart API -> codec -> FRB -> Rust -> redb, including range planner and multi-index intersection paths.
- [Query / Index 0.3 contract](docs/QUERY_INDEX_03.md) — query semantics, planner eligibility, equivalence rules, and persisted-index security.
- [Project handoff](docs/PROJECT_HANDOFF.md) — current implementation state and sequencing.
- [Testing strategy](docs/TESTING.md) — Dart/Rust test matrix, process-kill durability, benchmarks, profiles, and CI gates.
- [Native feature profiles](docs/NATIVE_FEATURE_PROFILES.md) — minimal/encryption/full contracts.
- [Cargo feature + size handoff](docs/CARGO_FEATURE_SIZE_HANDOFF.md) — feature/profile and size-measurement policy.
- [Plaintext -> encrypted migration](docs/PLAINTEXT_ENCRYPTION_MIGRATION.md) — migration API and atomicity contract.
- [Hive functional parity audit](docs/HIVE_FUNCTIONAL_PARITY.md) — release gate for the 1.0 functional-replacement claim.
- [Future native tree shaking](docs/FUTURE_NATIVE_TREE_SHAKING.md) — deferred Dart 3.13 native optimization policy.

## Test suite

Coverage includes minimum-SDK and current Flutter checks, native lifecycle/watch semantics, FRB round trips, encryption/migration, process-kill durability, query AST behavior, scan/index equivalence, range/index equivalence, multi-index AND intersection, persisted-index mutation maintenance, encrypted index rejection, FRB drift detection, all three Rust profiles on Ubuntu/macOS/Windows, native-size reproducibility, and Android/iOS/macOS/Linux/Windows example compilation.

## Roadmap

### 0.3.x — Query & migration

Implemented foundation:

- declarative native query AST;
- one-call native scan executor;
- persisted scalar secondary-index definitions/entries;
- transactional index maintenance;
- encrypted-index safety restrictions;
- equality and range index planner with scan/index equivalence coverage;
- multi-index candidate intersection for AND groups.

Next:

- improve persisted-index lookup efficiency without assuming raw MessagePack numeric byte ordering;
- consider one-redb-read-transaction query execution;
- explicit sort contract / `sortBy`;
- query/index benchmark scenarios after semantics stabilize;
- Hive CE migration design/implementation.

### 0.4.x — Production hardening

- controlled cross-commit binary-size regression policy;
- package-quality hardening;
- broader database comparisons.

### 0.9.x — Hive Functional Parity Audit

Refresh the audit against the then-current Hive CE release and close every practical `Gap` before 1.0.

### 1.0.0 — Stable

- Hive functional parity audit passes;
- stable storage/API contract;
- IndexedDB Web fallback;
- pub.dev release.

## License

MIT

### Persisted-index lookup optimization

Index-backed queries bound redb iteration to the selected persisted index name rather than scanning unrelated `index_entries`. Range predicates still decode stored MessagePack scalars and use the query comparator; raw MessagePack byte order is not used as numeric order.

