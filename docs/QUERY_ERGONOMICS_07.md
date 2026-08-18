# dxtr_box 0.7 — Query Ergonomics

## Goal

Make common Dxtr_Box queries substantially easier to read and write without replacing the existing query engine, changing durable storage, or turning Dxtr_Box into an ORM/schema framework.

The fluent API remains an additive Dart-side authoring layer over the existing `BoxQuery` AST:

```text
Fluent Dart API
      |
      v
existing BoxQuery / QueryFilter AST
      |
      v
existing serialization / FRB
      |
      v
existing Rust planner + indexes + authoritative record checks
```

`Box.query(BoxQuery)` remains first-class for advanced and dynamic composition.

## Milestone sequence

```text
PR1 — fluent queryWhere/comparison/AND/OR/grouping builder: merged (#44)
PR2 — orderBy/offset/limit/find ergonomics: merged (#45)
PR3 — optional DxtrField<T> typed field metadata: active
PR4 — README/examples/API equivalence/compatibility closure
```

## Entry-point compatibility decision

`Box` already exposes the legacy compatibility method:

```dart
Future<List<MapEntry<String, dynamic>>> where(
  bool Function(dynamic) test,
)
```

Dart does not support method overloading, and an instance method shadows an extension method with the same name. Therefore 0.7 keeps the legacy method intact and uses the collision-free fluent entry point:

```dart
box.queryWhere('field')
```

This preserves source typing and avoids weakening the public API merely to save a few characters.

## PR1 — fluent predicates

PR #44 added a fluent AST builder covering every existing comparison operator while retaining direct `Box.query` execution:

```dart
final query = box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .build();

final users = await box.query(query);
```

Standalone AST composition remains available:

```dart
final query = BoxQueryBuilder
    .where('score').between(50, 100)
    .build();
```

Supported comparison methods map one-to-one onto the existing `QueryOperator` contract:

```text
equals        -> equal
notEquals     -> notEqual
gt            -> greaterThan
gte           -> greaterThanOrEqual
lt            -> lessThan
lte           -> lessThanOrEqual
between       -> between
isNull        -> isNull
isNotNull     -> isNotNull
```

Mixed `AND` / `OR` chains are intentionally left-associative. Use `andGroup` / `orGroup` when grouping matters.

## PR2 — result, sort, pagination, and execution ergonomics

PR #45 extends the same Dart builder with result options that compile directly into existing `BoxQuery` fields:

```dart
final users = await box
    .queryWhere('status').equals('active')
    .and('age').gte(18)
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

Supported result options:

```text
orderBy(field, descending: false, nulls: QueryNullOrder.last)
offset(n)
limit(n)
```

Standalone `BoxQueryBuilder` remains a pure AST builder and therefore exposes `build()` but not `find()`. The `box.queryWhere(...)` path retains the originating `Box` through bound builder stages, so terminal `find()` is available only when execution context exists by construction.

`find()` delegates directly to the existing `Box.query(build())` path. No second execution, filtering, sorting, serialization, or native query path is introduced.

`findFirst`, `exists`, and `count` remain intentionally deferred until efficient native-backed operations exist; 0.7 does not materialize full result sets in Dart merely to provide convenience terminals.

## PR3 — optional typed field metadata

PR3 adds `DxtrField<T>` as opt-in reusable Dart metadata for a field path:

```dart
const status = DxtrField<String>('status');
const age = DxtrField<int>('profile.age');
const name = DxtrField<String>('name');
```

`DxtrField<T>` is **not a schema definition**. It does not register fields, alter storage, generate serializers, create indexes, or require code generation. The underlying runtime field identity remains the same string/dotted path consumed by `QueryComparison` and `QuerySort`.

Typed standalone composition starts from the field itself:

```dart
final query = status
    .where().equals('active')
    .andField(age).gte(18)
    .orderByField(name)
    .limit(20)
    .build();
```

Typed box-bound execution uses the additive entry point:

```dart
final users = await box
    .queryWhereField(status).equals('active')
    .andField(age).gte(18)
    .orderByField(name)
    .limit(20)
    .find();
```

Explicit groups can also use typed metadata:

```dart
final query = status
    .where().equals('active')
    .andGroup(
      (group) => group
          .whereField(age).gte(18)
          .orField(name).equals('admin'),
    )
    .build();
```

The value type carried by `DxtrField<T>` is enforced by Dart at the fluent authoring boundary. Every typed method then delegates to the existing untyped builder, so generated query objects remain structurally equivalent to direct `BoxQuery` construction.

String paths remain first-class and may be mixed with typed metadata. PR3 deliberately does not change the existing `where(String)`, `queryWhere(String)`, `and(String)`, `or(String)`, or `orderBy(String)` signatures because doing so would weaken their compile-time contracts.

### PR3 invariants

PR3 must not introduce:

- mandatory schema registration;
- model/entity generation;
- code generation;
- runtime reflection;
- automatic index creation;
- Dart-side filtering or sorting;
- a second query AST;
- FRB changes;
- Rust query-engine changes;
- storage-format changes;
- native-profile changes.

Malformed dotted paths continue to fail through the same existing `QueryComparison` / `QuerySort` validation when the typed field is used.

## Correctness contract

0.7 query ergonomics must not:

- add Dart-side filtering or sorting;
- duplicate Rust planner logic;
- add a second query AST or wire representation;
- change query serialization semantics;
- change index selection semantics;
- change encrypted equality-index behavior;
- change encrypted ordered/range scan-backed behavior;
- change `dxtr_box/1`;
- change native profiles or FRB bindings;
- weaken authoritative primary-record predicate rechecks.

## Explicit non-goals

Do not add in 0.7 without a separate product decision:

- SQL string parsing;
- ORM/entity repositories;
- mandatory schema/code generation;
- LINQ-style operator-heavy DSLs;
- overloaded boolean operators for query expressions;
- a second native query engine;
- a second wire/query AST;
- Dart-side post-filtering that bypasses the native planner;
- automatic index creation hidden inside fluent query calls;
- index-backed ORDER BY;
- encrypted order-revealing persisted indexes.

## Compatibility rules

0.7 query ergonomics must preserve:

- legacy `Box.where(bool Function(dynamic))` compatibility behavior;
- string-path query authoring as first-class API;
- `Box.query(BoxQuery)` as the canonical advanced query API;
- the existing native query execution path;
- one native query crossing per executed query;
- authoritative primary-record re-read and full predicate re-evaluation;
- deterministic sort-before-pagination semantics;
- `dxtr_box/1` storage compatibility;
- Dart >= 3.4 / Flutter >= 3.22;
- exactly `minimal | encryption | full` native profiles;
- FRB 2.8.0 and redb 2.1.0 unless separately reprioritized.

## Acceptance criteria

PR1 and PR2 are complete in merged PRs #44 and #45.

PR3 requires:

1. `DxtrField<T>` is optional reusable typed metadata over the existing field path;
2. typed equality/range comparison values are checked by Dart at authoring time;
3. typed AND/OR continuation and typed sorting remain available without replacing string APIs;
4. a typed box-bound entry point retains terminal `find()`;
5. explicit groups can start/continue with typed fields;
6. typed and manual/string forms compile to the same existing `BoxQuery` AST semantics;
7. no schema registry, codegen, ORM, reflection, or hidden index behavior is introduced;
8. no Rust/FRB/storage-format/native-profile change is introduced.

PR4 owns final README/examples/API-equivalence/compatibility closure and publication-level documentation sync.

The intended 0.7 outcome is a compact native local database with easier box-style query ergonomics, not a larger ORM or application framework.
