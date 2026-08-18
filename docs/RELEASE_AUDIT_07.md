# dxtr_box 0.7 Release Audit

## Scope

0.7 Query Ergonomics is a Dart-side authoring milestone over the existing query/runtime contract. It does not introduce a second query engine, second wire AST, storage-format change, or new native capability profile.

Implementation sequence:

```text
PR #44 — fluent queryWhere/comparison/AND/OR/grouping builder
PR #45 — orderBy/offset/limit + bound terminal find()
PR #46 — optional BoxField<T> typed metadata + functional API naming
PR4    — documentation/API equivalence/compatibility closure
```

## Public API equivalence matrix

| Authoring path | Field representation | Build result | Executes through | Status |
| --- | --- | --- | --- | --- |
| `Box.query(BoxQuery)` | direct string-path AST | `BoxQuery` | existing native query path | first-class |
| `BoxQueryBuilder.where(String)` | string path | `BoxQuery` | caller passes to `Box.query` | first-class |
| `box.queryWhere(String)` | string path | bound `BoxQuery` | `find()` -> `Box.query(build())` | first-class |
| `BoxField<T>.where()` | typed metadata wrapping string path | `BoxQuery` | caller passes to `Box.query` | optional first-class |
| `box.queryWhereField(BoxField<T>)` | typed metadata wrapping string path | bound `BoxQuery` | `find()` -> `Box.query(build())` | optional first-class |
| `Box.where(predicate)` | Dart predicate callback | legacy scan API | existing legacy behavior | preserved compatibility |

All fluent/typed declarative paths converge on the existing `BoxQuery` / `QueryFilter` representation before serialization.

## Comparison equivalence

```text
equals        -> QueryOperator.equal
notEquals     -> QueryOperator.notEqual
gt            -> QueryOperator.greaterThan
gte           -> QueryOperator.greaterThanOrEqual
lt            -> QueryOperator.lessThan
lte           -> QueryOperator.lessThanOrEqual
between       -> QueryOperator.between
isNull        -> QueryOperator.isNull
isNotNull     -> QueryOperator.isNotNull
```

Typed metadata delegates to the same operations and therefore does not create a separate semantic layer.

## Boolean/grouping equivalence

- `and` / `andField` compile to the same AND structure.
- `or` / `orField` compile to the same OR structure.
- `andGroup` / `orGroup` preserve explicit nested group structure.
- mixed AND/OR chaining remains left-associative.
- malformed dotted paths continue through existing query validation.

## Sort/pagination equivalence

```text
orderBy / orderByField -> BoxQuery.sortBy
offset                  -> BoxQuery.offset
limit                   -> BoxQuery.limit
find()                  -> Box.query(build())
```

Standalone builders do not expose `find()` because they intentionally carry no execution context.

`findFirst`, `exists`, and `count` remain deferred until efficient native-backed operations exist.

## Naming compatibility

Primary functional names:

```text
BoxStore
BoxCodec
NativeBoxApi
FrbNativeBoxApi
UnavailableNativeBoxApi
BoxStoreMigrationInternals
BoxField<T>
```

Deprecated compatibility shims remain where source compatibility requires them, notably `DxtrBox` and old codec/native seam identifiers.

New implementation, examples, and user-facing documentation should use functional names.

The following identities intentionally do **not** change:

```text
package:       dxtr_box
native lib:    rust_lib_dxtr_box
file marker:   .dxtr
format:        dxtr_box/1
wire tags:     @dxtr:*
```

These are package/durable compatibility identities rather than ordinary domain type names.

## Storage/runtime invariants

0.7 preserves:

- `dxtr_box/1`;
- primary data as authoritative;
- transactional primary/index mutation maintenance;
- full predicate re-evaluation after index candidate narrowing;
- plaintext equality/range index behavior;
- encrypted equality index behavior using keyed BLAKE2b tokens;
- encrypted ordered/range authoritative scan fallback;
- deterministic semantic sorting before pagination;
- one native query call per executed declarative query;
- authenticated decrypt/read behavior;
- no Dart whole-box cache;
- no reusable stale read snapshot.

## Dependency/profile invariants

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
profiles = minimal | encryption | full
```

No fourth profile is introduced.

## Explicitly absent from 0.7

- ORM/entity repositories;
- mandatory schema registration;
- model serialization generation;
- runtime reflection;
- SQL parser;
- automatic index creation;
- Dart-side filtering/sorting for declarative queries;
- second query AST;
- second native query engine;
- index-backed ORDER BY;
- encrypted order-preserving/range index design.

## Documentation closure

PR4 synchronizes:

- `README.md`;
- `CHANGELOG.md`;
- `docs/PROJECT_HANDOFF.md`;
- `docs/CODE_WALKTHROUGH.md`;
- `docs/QUERY_ERGONOMICS_07.md`;
- this audit.

The example already uses `BoxStore` after PR #46.

## Merge acceptance

0.7 is closed only when PR4 passes the repository full quality bar, including:

```text
Fast CI
Dart full tests
Minimum SDK / Flutter 3.22 + Dart 3.4
Rust / three profiles
Rust cross-platform checks
Native integration
Storage/migration/query regression
FRB generated bindings
Package/docs + pub dry-run
Native-size policy
Benchmark correctness smoke
Android/Linux/Windows/macOS/iOS staged consumers
Merge Gate / full quality bar
```

After merge, `main` is the clean baseline for 0.8 Rust-native API / Multi-frontend Foundation.
