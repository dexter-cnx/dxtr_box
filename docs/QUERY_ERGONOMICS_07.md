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
PR1 — fluent queryWhere/comparison/AND/OR/grouping builder
PR2 — orderBy/offset/limit/find ergonomics; efficient native-backed convenience terminals only
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

PR1 adds a fluent AST builder covering every existing comparison operator while keeping execution on the existing `Box.query` path:

```dart
final query = box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .build();

final users = await box.query(query);
```

The standalone entry point is also available when a box instance is not needed while composing the AST:

```dart
final query = BoxQueryBuilder
    .where('score').between(50, 100)
    .build();
```

Supported PR1 comparison methods map one-to-one onto the existing `QueryOperator` contract:

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

No hidden SQL-style precedence is introduced.

When grouping matters, use `andGroup` / `orGroup` explicitly:

```dart
final query = BoxQueryBuilder
    .where('status').equals('active')
    .andGroup(
      (group) => group
          .where('profile.age').gte(18)
          .or('role').equals('admin'),
    )
    .build();
```

This compiles to the existing nested `QueryGroup` AST.

## PR1 correctness contract

PR1 is Dart-only query authoring ergonomics. It must not:

- add Dart-side filtering or sorting;
- duplicate Rust planner logic;
- add a second query AST or wire representation;
- change query serialization;
- change index selection semantics;
- change encrypted equality-index behavior;
- change encrypted ordered/range scan-backed behavior;
- change `dxtr_box/1`;
- change native profiles or FRB bindings;
- weaken authoritative primary-record predicate rechecks.

Field validation remains inherited from `QueryComparison`, so malformed dotted paths fail under the same contract as direct manual AST construction.

## PR2 target

PR1 intentionally stops at `build()` plus existing `Box.query(...)` execution.

PR2 owns the final common-query shape:

```dart
final users = await box
    .queryWhere('status').equals('active')
    .and('age').gte(18)
    .orderBy('name')
    .limit(20)
    .find();
```

PR2 scope:

- `orderBy`, including descending and null-placement options compatible with `QuerySort`;
- `offset`;
- `limit`;
- terminal `find()` bound to the originating `Box`;
- evaluate `findFirst`, `exists`, and `count` only when backed by efficient native operations rather than full-result materialization across FRB.

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

0.7 succeeds when common queries are shorter and more readable while preserving one query model internally.

PR1 specifically requires:

1. fluent filtering can start with `box.queryWhere(...)` or `BoxQueryBuilder.where(...)`;
2. every existing comparison operator has a fluent equivalent;
3. AND/OR chaining has documented deterministic precedence;
4. explicit nested grouping is supported;
5. fluent queries compile to the existing `BoxQuery` AST;
6. direct `Box.query(BoxQuery)` remains supported;
7. legacy `Box.where(predicate)` remains source-compatible;
8. nested field validation remains unchanged;
9. AST-equivalence tests cover fluent versus direct construction;
10. no Rust/FRB/storage-format/native-profile change is introduced.

The intended 0.7 outcome is a compact native local database with easier box-style query ergonomics, not a larger ORM or application framework.
