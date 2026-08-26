# Fluent Box Query API Specification

## Status

Future-facing design specification for `dxtr_box`. This document does not change runtime behavior by itself.

## Goal

Make a document-oriented fluent query API the primary Dart query experience while preserving the existing authoritative Rust query representation, planner, index execution, encryption semantics, and redb storage engine.

The API should feel natural to Flutter/Dart developers without borrowing Firebase or Firestore product naming.

Recommended public feature name: **Fluent Box Query API**.

Recommended primary type: `BoxQuery`.

## Design principles

1. Dart builder operations are local-only and must not cross FRB individually.
2. A terminal operation should normally result in one Dart -> FRB -> Rust execution request.
3. Filter, sort, pagination, count, and existence checks execute in Rust.
4. Persisted indexes are planner concerns, not semantic requirements unless explicitly requested.
5. All frontends converge onto one canonical Rust query AST and planner.
6. Typed field metadata remains optional; no ORM, schema registration, or model code generation is required.
7. SQL support, if added later, is another parser/frontend over the same canonical query representation rather than a second query engine.

## Core model

```text
Box
  └─ Record
      ├─ key
      └─ structured value
          ├─ scalar fields
          ├─ nested maps
          └─ lists
```

Terminology stays native to `dxtr_box`: `Box`, `Record`, `BoxQuery`, and `BoxField<T>` rather than collection/document terminology.

## Primary Dart API

```dart
final users = await box
    .query()
    .where('status', isEqualTo: 'active')
    .where('age', isGreaterThanOrEqualTo: 18)
    .orderBy('name')
    .limit(20)
    .get();
```

Chained `where()` calls use `AND` semantics by default.

### Comparison operators

```dart
.where('age', isEqualTo: 18)
.where('age', isNotEqualTo: 18)
.where('age', isLessThan: 18)
.where('age', isLessThanOrEqualTo: 18)
.where('age', isGreaterThan: 18)
.where('age', isGreaterThanOrEqualTo: 18)
```

A single `where()` call accepts one comparison mode. Invalid combinations should fail before crossing FRB when Dart can validate them safely; Rust remains authoritative for execution semantics.

### Set operators

Initial target:

```dart
.where('status', whereIn: ['active', 'pending'])
.where('status', whereNotIn: ['deleted', 'blocked'])
```

Array operators such as `arrayContains` and `arrayContainsAny` are deferred until their persisted-index semantics are explicitly designed.

### Nested fields

Use canonical dotted field paths:

```dart
final users = await box
    .query()
    .where('profile.age', isGreaterThanOrEqualTo: 18)
    .where('address.country', isEqualTo: 'TH')
    .get();
```

### Optional typed fields

```dart
const status = BoxField<String>('status');
const age = BoxField<int>('profile.age');

final users = await box
    .query()
    .whereField(status, isEqualTo: 'active')
    .whereField(age, isGreaterThanOrEqualTo: 18)
    .get();
```

`BoxField<T>` remains authoring metadata only. It must not introduce schema registration or code generation requirements.

## Ordering

```dart
final users = await box
    .query()
    .orderBy('name')
    .orderBy('createdAt', descending: true)
    .get();
```

Ordering must be deterministic. When explicit ordering fields compare equal, the record key should provide a stable tie-breaker.

## Limit and offset

```dart
final users = await box
    .query()
    .offset(20)
    .limit(20)
    .get();
```

`offset()` is supported for compatibility and small-result convenience but should not be the preferred large-dataset pagination strategy.

## Cursor pagination

Preferred future pagination model:

```dart
final firstPage = await box
    .query()
    .orderBy('createdAt')
    .limit(20)
    .get();

final secondPage = await box
    .query()
    .orderBy('createdAt')
    .startAfter(firstPage.last)
    .limit(20)
    .get();
```

Candidate cursor operators:

```text
startAt
startAfter
endAt
endBefore
```

Cursor semantics must be tied to effective ordering and stable record-key tie-breaking.

## Results

Preferred result shape:

```dart
class BoxQueryResult<T> {
  final List<BoxRecord<T>> records;

  bool get isEmpty;
  bool get isNotEmpty;
  int get length;
  BoxRecord<T>? get firstOrNull;
  BoxRecord<T>? get lastOrNull;
}

class BoxRecord<T> {
  final String key;
  final T value;
}
```

A convenience values-only terminal may be provided:

```dart
final values = await box
    .query()
    .where('active', isEqualTo: true)
    .values();
```

## Terminal operations

Initial candidates:

```text
get
values
first
firstOrNull
single
count
exists
explain
```

Examples:

```dart
final count = await box
    .query()
    .where('status', isEqualTo: 'active')
    .count();

final exists = await box
    .query()
    .where('email', isEqualTo: email)
    .exists();
```

`count()` must count in Rust rather than fetching all matching records into Dart. `exists()` should stop at the first authoritative match.

## Explicit boolean groups

Avoid ambiguous fluent boolean precedence. Use explicit groups for OR/nesting:

```dart
final users = await box
    .query()
    .whereAll([
      BoxCondition('active', isEqualTo: true),
      BoxGroup.any([
        BoxCondition('role', isEqualTo: 'admin'),
        BoxCondition('role', isEqualTo: 'editor'),
      ]),
    ])
    .get();
```

Canonical predicate:

```text
AND
├─ active == true
└─ OR
   ├─ role == admin
   └─ role == editor
```

## Query immutability

The builder should be immutable so a base query can be safely reused and composed:

```dart
final active = box
    .query()
    .where('active', isEqualTo: true);

final admins = await active
    .where('role', isEqualTo: 'admin')
    .get();

final editors = await active
    .where('role', isEqualTo: 'editor')
    .get();
```

## Index behavior

Normal queries do not require explicit index selection:

```text
query request
    ↓
usable persisted index?
    ├─ yes -> indexed narrowing
    └─ no  -> authoritative primary scan
```

The query result semantics must remain correct with or without an index.

A future production-safety feature may require indexed execution explicitly:

```dart
final users = await box
    .query()
    .where('status', isEqualTo: 'active')
    .requireIndex()
    .get();
```

If no valid plan can satisfy that requirement, return a structured missing-index error rather than silently scanning.

## Explain

High-value future diagnostic API:

```dart
final plan = await box
    .query()
    .where('status', isEqualTo: 'active')
    .orderBy('createdAt')
    .explain();
```

Potential output model:

```text
BoxQueryPlan
  strategy: indexScan
  index: status_idx
  scannedEntries: 418
  postFilter: none
  sort: inMemory
  limit: 20
```

Inspector tooling should reuse the same planner diagnostics rather than introducing a separate explain implementation.

## Encryption semantics

The public fluent API remains the same for plaintext and encrypted boxes.

Planner behavior follows existing storage contracts:

```text
plaintext equality/range
  -> persisted index when available

encrypted equality
  -> keyed equality index when available

ordered/range predicate over encrypted value
  -> authoritative decrypt/authenticate + scan/recheck
```

Encryption capability must not produce a second public query language.

## FRB execution boundary

Required execution model:

```text
Dart BoxQuery builder
    ↓ local-only construction
canonical query request
    ↓ one terminal execution call
FRB
    ↓
Rust query AST/planner
    ↓
index or scan
    ↓
filter / sort / cursor / limit
    ↓
result
```

Do not execute `where`, `orderBy`, `limit`, or other builder steps as separate native calls.

This is important because current profiling shows the Dart/FRB boundary dominates very small point-read workloads while larger batches and indexed queries amortize that fixed cost well.

## Native Rust frontend

Rust retains idiomatic Rust naming while converging onto the same canonical semantics:

```rust
let users = box_
    .query()
    .where_("status")
    .equals("active")
    .and("age")
    .gte(18)
    .order_by("name", SortOrder::Ascending)
    .limit(20)
    .find()?;
```

Dart and Rust method names do not need to be identical. The canonical query representation and execution semantics do.

## Canonical architecture

```text
Dart Fluent Box Query ─┐
Rust Query Builder ────┼─> Canonical Rust Query AST
future SQL subset ─────┘
                              ↓
                         Query Planner
                              ↓
                  persisted index / scan
                              ↓
                             redb
```

No frontend gets its own query engine.

## Future SQL subset

If SQL-like syntax is later added, scope it as a convenience frontend only. A useful initial subset could include:

```text
SELECT
FROM
WHERE
AND / OR
= != < <= > >=
IN
ORDER BY
LIMIT
OFFSET
COUNT(*)
```

Do not position `dxtr_box` as a full SQL database unless full SQL semantics are intentionally implemented and supported. JOINs, CTEs, window functions, broad DDL, and full relational semantics are out of initial scope.

## Compatibility with existing Dart query API

Existing query APIs remain valid during introduction. Recommended migration sequence:

```text
Phase 1: existing API + new BoxQuery API
Phase 2: BoxQuery becomes documented primary API
Phase 3: old fluent API remains compatibility layer
Phase 4: deprecate only if maintenance cost justifies it
```

This work must not accidentally break the stable Dart public contract.

## Recommended naming set

```text
Box
BoxQuery
BoxCondition
BoxGroup
BoxField<T>
BoxQueryResult<T>
BoxRecord<T>
BoxQueryPlan
```

Recommended verbs:

```text
query
where
whereField
whereAll
whereAny
orderBy
orderByField
limit
offset
startAt
startAfter
endAt
endBefore
get
values
first
firstOrNull
single
count
exists
explain
```

## Initial delivery plan

### Phase A — primary fluent surface

- `query()` entry point
- comparison operators
- nested field paths
- `whereIn` / `whereNotIn`
- explicit AND / OR groups
- deterministic `orderBy`
- `limit` / `offset`
- `get`, `firstOrNull`, `count`, `exists`
- optional `BoxField<T>` integration
- immutable Dart builder
- one-call FRB terminal execution
- canonical Rust planner reuse
- semantic parity/regression tests against existing query execution

### Phase B — production query ergonomics

- cursor pagination
- `requireIndex`
- `explain`
- planner/index diagnostics
- benchmark evidence for boundary crossings and indexed/scan plans

### Phase C — conditional extensions

Only with consumer evidence:

- array operators
- projection
- reactive query watching
- aggregates beyond count
- SQL subset frontend

## Non-goals

This feature must not become:

- a Firebase/Firestore compatibility layer;
- a SQL engine rewrite;
- an ORM or mandatory schema system;
- a second query planner in Dart;
- a reason to move filtering/sorting back across the FRB boundary;
- a storage-format redesign without an explicit migration requirement.

## Product wording

Preferred documentation language:

> Fluent Box Queries provide expressive document-oriented querying with nested fields, persisted indexes, ordering, pagination, and native Rust execution.

Avoid Firebase, Firestore, or "SQL database" branding. The feature should remain recognizably `dxtr_box`.