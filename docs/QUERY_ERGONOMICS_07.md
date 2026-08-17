# dxtr_box 0.7 — Query Ergonomics

## Goal

Make common Dxtr_Box queries substantially easier to read and write without replacing the existing query engine, changing durable storage, or turning Dxtr_Box into an ORM/schema framework.

The 0.7 direction is a Dart-side ergonomics layer that compiles to the existing `BoxQuery` AST and therefore reuses the current serialization, FRB, Rust planner, persisted-index, encryption, sorting, and pagination paths.

```text
Fluent Dart API
      |
      v
existing BoxQuery AST
      |
      v
existing serialization / FRB
      |
      v
existing Rust query planner + indexes
```

The current `Box.query(BoxQuery)` API remains supported for advanced/dynamic composition. The fluent layer is additive and should not be a breaking change.

## Target usage

Common query:

```dart
final users = await box
    .where('status').equals('active')
    .and('age').gte(18)
    .orderBy('name')
    .limit(20)
    .find();
```

Range + sort:

```dart
final products = await box
    .where('price').between(100, 500)
    .and('category').equals('camera')
    .orderBy('price', descending: true)
    .find();
```

Nested field:

```dart
final result = await box
    .where('profile.country').equals('TH')
    .and('profile.age').between(20, 40)
    .find();
```

Grouped predicates should remain explicit rather than relying on operator-overloading magic:

```dart
final result = await box
    .where('status').equals('active')
    .andGroup((q) => q
        .where('role').equals('admin')
        .or('role').equals('moderator'))
    .find();
```

## Proposed fluent surface

Initial comparison helpers:

```text
where(field)
equals(value)
gt(value)
gte(value)
lt(value)
lte(value)
between(lower, upper)
isNull()
isNotNull()
and(field)
or(field)
andGroup(...)
orGroup(...)
orderBy(field, descending: false)
offset(n)
limit(n)
find()
```

Only expose predicates that map cleanly to the actual engine contract. Do not create Dart-only semantics that silently degrade to inefficient full-result filtering.

## Optional typed fields

Typed fields are desirable as an opt-in safety layer, while string field paths remain first-class:

```dart
const age = DxtrField<int>('age');
const name = DxtrField<String>('name');

final result = await box
    .where(age).gte(18)
    .and(name).equals('Dexter')
    .find();
```

This should provide compile-time value-type checking without requiring code generation or a mandatory schema.

Nested paths must continue to work with either raw strings or typed field metadata.

## Convenience operations

Potential convenience APIs include:

```text
findFirst(...)
exists(...)
count(...)
```

`exists()` and `count()` should only become public convenience APIs when backed by efficient native query operations. Do not implement them as `query().isNotEmpty` or `query().length` if that would materialize unnecessary records across FRB.

## Explicit non-goals

Do not add in the first 0.7 pass:

- SQL string parsing;
- ORM/entity repositories;
- mandatory schema/code generation;
- LINQ-style operator-heavy DSLs;
- overloaded boolean operators for query expressions;
- a second native query engine;
- a second wire/query AST;
- Dart-side post-filtering that bypasses the native planner;
- automatic index creation hidden inside fluent query calls.

The API should stay simple, predictable, and visibly connected to the existing Dxtr_Box query semantics.

## Compatibility and architecture rules

0.7 query ergonomics must preserve:

- `Box.query(BoxQuery)` as the canonical advanced query API;
- the existing native query execution path;
- one native query crossing per query;
- authoritative primary-record re-read and full predicate re-evaluation;
- encrypted equality-index behavior;
- encrypted ordered/range scan-backed behavior;
- deterministic sort-before-pagination semantics;
- `dxtr_box/1` storage compatibility;
- Dart >=3.4 / Flutter >=3.22 unless a separate compatibility decision changes them;
- exactly `minimal | encryption | full` native profiles.

The fluent builder should compile into the same AST used by `BoxQuery`, not introduce parallel semantics.

## Recommended four-PR sequence

### PR1 — fluent predicates

- `box.where(...)` entry point;
- comparison helpers;
- `and` / `or` composition;
- grouped predicates;
- AST equivalence tests against direct `BoxQuery` construction.

### PR2 — result/sort/pagination ergonomics

- `orderBy`;
- `offset`;
- `limit`;
- `find`;
- evaluate `findFirst`, `exists`, and `count` only where implementation remains efficient and native-backed.

### PR3 — optional typed fields

- `DxtrField<T>` or equivalent lightweight typed metadata;
- nested field support;
- compile-time type safety tests;
- no mandatory code generation.

### PR4 — docs/examples/compatibility closure

- README examples centered on fluent queries;
- code walkthrough and API documentation;
- old/new API equivalence coverage;
- compatibility audit and full merge quality bar.

## Acceptance criteria

0.7 is successful when common queries are shorter and more readable while preserving a single query model internally.

Specifically:

1. common filtering can start with `box.where(...)`;
2. fluent queries compile to the existing `BoxQuery` AST;
3. direct `Box.query(BoxQuery)` remains supported;
4. fluent and direct forms produce equivalent query semantics;
5. nested fields remain supported;
6. grouping has explicit precedence semantics;
7. sort/offset/limit preserve current engine ordering rules;
8. no implicit Dart-side materialization/filtering is introduced;
9. optional typed fields do not require a schema framework;
10. no storage-format, native-profile, encryption, or query-planner regression is introduced.

## Product outcome

The intended public feel is:

```dart
final adults = await users
    .where('active').equals(true)
    .and('age').gte(18)
    .orderBy('name')
    .find();
```

while advanced code can still construct and reuse `BoxQuery` directly.

This keeps Dxtr_Box a compact native local database with box-style ergonomics rather than expanding it into a full ORM or application framework.
