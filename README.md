# dxtr_box

[![CI](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml/badge.svg)](https://github.com/dexter-cnx/dxtr_box/actions/workflows/ci.yml)

**Native local database for Flutter, forged in Rust. By Dxtr.**

`dxtr_box` is a Rust/redb-backed local database for Flutter with ACID persistence, authenticated encryption, native queries, persisted indexes, watch streams, migration tooling, and a simple box-style Dart API. No model code generation is required.

> Status: **0.7 Query Ergonomics is complete pending closure PR merge.** PR #44 added fluent predicates, PR #45 added sort/pagination/bound `find()`, and PR #46 added optional `BoxField<T>` typed field metadata plus functional API naming. The package remains pre-1.0; public API and storage format are not yet declared stable.

## Key features

- Rust/redb ACID storage outside the Dart heap.
- Async box-style CRUD and transactional bulk operations.
- Authoritative optimized point reads and one-snapshot `getAll`.
- Declarative native queries with nested fields, groups, sort, offset, and limit.
- Fluent query builder with bound terminal `find()`.
- Optional `BoxField<T>` typed field-path metadata without schema/codegen/ORM requirements.
- Persisted plaintext equality/range indexes.
- Encrypted equality indexes using domain-separated keyed BLAKE2b tokens under `full`.
- Argon2 + ChaCha20Poly1305 authenticated encryption.
- Native cross-handle watch events through Flutter Rust Bridge.
- Explicit plaintext-to-encrypted migration and optional Hive CE migration tooling.
- Android, iOS, macOS, Linux, and Windows staged consumer validation.
- Self-contained Flutter FFI plugin topology.

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

## Basic API

Use `BoxStore` as the primary storage facade:

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

`DxtrBox` remains available only as a deprecated source-compatibility shim. New code and documentation should use `BoxStore`.

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

## Fluent queries

### String-path authoring

```dart
final users = await box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

Supported comparisons:

```text
equals / notEquals
gt / gte / lt / lte
between
isNull / isNotNull
and / or
andGroup / orGroup
```

Mixed `AND` / `OR` chains are left-associative. Use explicit groups when precedence matters.

### Optional typed field metadata

```dart
const status = BoxField<String>('status');
const age = BoxField<int>('profile.age');
const name = BoxField<String>('name');

final users = await box
    .queryWhereField(status).equals('active')
    .andField(age).gte(18)
    .orderByField(name)
    .limit(20)
    .find();
```

`BoxField<T>` is metadata only. It does not register a schema, generate serializers, create indexes, use reflection, or alter storage. String-path APIs remain first-class and may be mixed with typed metadata.

### Standalone AST composition

```dart
final query = BoxQueryBuilder
    .where('price').between(100, 500)
    .and('category').equals('camera')
    .orderBy('price')
    .limit(20)
    .build();

final rows = await box.query(query);
```

Standalone builders intentionally expose `build()` but not `find()` because they do not carry a `Box` execution context.

### Direct declarative AST

`Box.query(BoxQuery)` remains first-class for advanced or dynamic composition:

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
    sortBy: [
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

The fluent and typed APIs compile to the same `BoxQuery` / `QueryFilter` AST and execute through the same Rust planner. There is no Dart-side query engine or second wire representation.

## Query execution guarantees

- one native call per executed declarative query;
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
  const IndexDefinition(name: 'by-age', field: 'profile.age'),
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

Ordinary API/domain symbols use functional names such as `Box`, `BoxStore`, `BoxCodec`, `NativeBoxApi`, `BoxQueryBuilder`, and `BoxField`.

## CI and validation

The merge quality bar covers:

- format/analyze/tests;
- Flutter 3.22 / Dart 3.4 minimum compatibility;
- exact `minimal | encryption | full` Rust profiles;
- native integration;
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

- `docs/QUERY_ERGONOMICS_07.md` — 0.7 fluent/typed query design.
- `docs/RELEASE_AUDIT_07.md` — 0.7 closure and API equivalence matrix.
- `docs/PROJECT_HANDOFF.md` — current project state and next milestone.
- `docs/CODE_WALKTHROUGH.md` — current runtime/API execution paths.
- `docs/QUERY_INDEX_ENCRYPTION_06.md` — encrypted index contract.

## Direction after 0.7

The next planned milestone is **0.8 Rust-native API / Multi-frontend Foundation**: a first-class Rust frontend and the existing Dart frontend over one shared authoritative Rust storage core. GPUI may consume the Rust frontend later, but is not a dependency of Dxtr_Box.

See `docs/PROJECT_HANDOFF.md` for the guarded 0.8 plan.
