# dxtr_box 0.7 — Query Ergonomics

## Goal

Make common Dxtr_Box queries substantially easier to read and write without replacing the existing query engine, changing durable storage, or turning Dxtr_Box into an ORM/schema framework.

The fluent API is an additive Dart-side authoring layer over the existing `BoxQuery` AST:

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
PR2 — orderBy/offset/limit/find ergonomics: active
PR3 — optional DxtrField<T> typed field metadata; no mandatory schema/codegen
PR4 — README/examples/API equivalence/compatibility closure
```

## Entry-point compatibility decision

`Box` already exposes the legacy compatibility method:

```dart
Future<List<MapEntry<String, dynamic>>> where(
  bool Function(dynamic) test,
)
```

Dart does not support method overloading, and an instance method shadows an extension method with the same name. Therefore adding `box.where('field')` would either break the existing public surface or require a dynamically typed dispatch API.

0.7 keeps the legacy method intact and uses the collision-free fluent entry point:

```dart
box.queryWhere('field')
```

This preserves source typing and avoids weakening the public API merely to save five characters. A future breaking 1.0 API cleanup may reconsider naming separately; 0.7 does not.

## PR1 accepted public surface

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

## Boolean semantics

Mixed `AND` / `OR` chains are intentionally **left-associative**.

```dart
BoxQueryBuilder
    .where('a').equals(1)
    .and('b').equals(2)
    .or('c').equals(3)
```

means:

```text
(a == 1 AND b == 2) OR c == 3
```

No hidden SQL-style precedence is introduced. Use `andGroup` / `orGroup` when grouping matters.

## PR2 — result, sort, pagination, and execution ergonomics

PR2 extends the same Dart builder with result options that compile directly into existing `BoxQuery` fields:

```dart
final users = await box
    .queryWhere('status').equals('active')
    .and('age').gte(18)
    .orderBy('name')
    .limit(20)
    .find();
```

Supported result options:

```text
orderBy(field, descending: false, nulls: QueryNullOrder.last)
offset(n)
limit(n)
```

Multiple `orderBy` calls preserve declaration order and map one-to-one to `BoxQuery.sortBy`. `offset` and `limit` retain the existing validation and native sort-before-pagination semantics.

### Bound versus standalone builders

PR2 intentionally keeps standalone composition pure:

```dart
final query = BoxQueryBuilder
    .where('status').equals('active')
    .orderBy('name')
    .offset(10)
    .limit(20)
    .build();
```

Standalone `BoxQueryBuilder` does **not** expose `find()` because it has no execution context.

The `box.queryWhere(...)` path retains the originating `Box` through dedicated bound builder stages:

```text
Box
  -> BoundQueryFieldBuilder
  -> BoundBoxQueryBuilder
  -> build() or find()
```

This avoids nullable-box state and avoids a runtime "missing execution context" failure mode. `find()` is available only when a `Box` is present by construction.

Terminal execution remains exactly:

```text
find()
  -> build()
  -> Box.query(BoxQuery)
  -> existing serialization / FRB
  -> existing Rust planner/index execution
```

No second execution path is introduced.

### Convenience terminals intentionally not added

`findFirst`, `exists`, and `count` are not added in PR2. They should become public only when backed by efficient native operations rather than materializing full result sets across FRB and then truncating/counting in Dart.

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

Field validation remains inherited from `QueryComparison` / `QuerySort`, so malformed dotted paths fail under the same contract as direct manual AST construction.

## PR3 optional typed fields

Typed fields remain opt-in and string paths remain first-class:

```dart
const age = DxtrField<int>('age');
const name = DxtrField<String>('name');
```

No mandatory schema, ORM, or code generation is allowed merely to support typed query metadata.

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

PR1 is complete in merged PR #44.

PR2 requires:

1. `orderBy`, `offset`, and `limit` compile into the existing `BoxQuery` fields;
2. ascending/descending and null placement preserve `QuerySort` semantics;
3. multiple sorts preserve declaration order;
4. invalid offset/limit values fail before execution;
5. standalone `BoxQueryBuilder` remains a pure AST builder;
6. `find()` exists only on a builder bound to an originating `Box`;
7. `find()` delegates to the existing `Box.query` path rather than creating a new execution path;
8. fluent/manual AST equivalence remains covered by tests;
9. no `findFirst`/`exists`/`count` materialization shortcuts are introduced;
10. no Rust/FRB/storage-format/native-profile change is introduced.

The intended 0.7 outcome is a compact native local database with easier box-style query ergonomics, not a larger ORM or application framework.
