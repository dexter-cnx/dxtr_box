# dxtr_box 1.3 Roadmap — Fluent Box Query

## Goal

`dxtr_box 1.3` makes **Fluent Box Query** the documented primary Dart query experience while preserving the existing storage engine, durable format, Rust planner, and compatibility-sensitive public contracts.

The detailed API design remains authoritative in `docs/FLUENT_BOX_QUERY_SPEC.md`.

## Release boundary

1.3 is a query developer-experience and execution-boundary release, not a storage-format or engine rewrite.

Required invariants:

- durable format remains `dxtr_box/1`;
- redb remains the authoritative storage engine unless a separate dependency-evaluation decision changes it;
- Dart and Rust query frontends converge on one canonical Rust query representation/planner;
- existing public query APIs remain source-compatible during 1.3;
- query-builder composition stays local to Dart and does not create extra FRB crossings;
- one terminal query operation normally maps to one native execution request;
- SQL syntax, reactive queries, and a redb major-version migration are not bundled into 1.3.

## Compatibility-safe Dart entry point

`Box` already exposes the stable execution API:

```dart
Future<List<MapEntry<String, dynamic>>> query(BoxQuery query)
```

Dart does not support overloading that method with a zero-argument `query()` returning a builder. Therefore 1.3 must not introduce a conflicting `query()` signature.

The compatibility-safe fluent entry point for 1.3 is:

```dart
box.queryBuilder()
```

The existing `box.query(BoxQuery)` execution API remains valid and source-compatible. A future breaking major release may reconsider the naming only through an explicit migration/versioning decision; 1.3 does not do so.

## Phase A — Primary Fluent Surface

Deliver the primary `BoxQuery` authoring surface:

- `box.queryBuilder()` entry point;
- immutable `BoxQuery` builder;
- dotted nested field paths;
- `==`, `!=`, `<`, `<=`, `>`, `>=`;
- `whereIn` / `whereNotIn`;
- explicit AND/OR grouping with deterministic precedence;
- deterministic `orderBy` with record-key tie-breaking;
- `limit` and compatibility `offset`;
- terminal `get`, `firstOrNull`, `count`, and `exists`;
- optional `BoxField<T>` typed field metadata;
- canonical Rust planner reuse;
- semantic parity tests against the current query path;
- boundary tests proving builder composition does not cross FRB;
- same-run Dart/FRB and Rust-native diagnostic evidence for representative query workloads.

Desired Dart surface:

```dart
final users = await box
    .queryBuilder()
    .where('status', isEqualTo: 'active')
    .where('profile.age', isGreaterThanOrEqualTo: 18)
    .orderBy('lastSeenAt', descending: true)
    .limit(50)
    .get();
```

## Phase B — Production Query Ergonomics

Complete 1.3 with production-oriented query controls:

- cursor pagination: `startAt`, `startAfter`, `endAt`, `endBefore`;
- `requireIndex()` to reject accidental full scans when requested;
- `explain()` returning structured planner/index diagnostics;
- Inspector CLI reuse of planner explain information where practical;
- scan-vs-index correctness and benchmark evidence;
- Dart/FRB-vs-native evidence for cursor and indexed-query paths;
- documentation migration examples from the current query API to `BoxQuery`.

Phase B does not remove the previous query API. Deprecation, if ever justified, requires a later compatibility decision backed by adoption evidence.

## Performance contract

1.3 must follow these rules:

1. `.where()`, grouping, `.orderBy()`, cursor construction, `.limit()`, and `.offset()` are Dart-local builder operations.
2. Terminal execution crosses the Dart/Rust boundary once under normal operation.
3. Filtering, sorting, index selection, `count`, and `exists` execute in Rust.
4. `count()` must not materialize all matching values in Dart merely to compute length.
5. `exists()` should stop after the first authoritative match.
6. Indexes are planner optimizations; query semantics remain correct without an index unless `requireIndex()` is explicitly requested.
7. Existing encrypted equality/range semantics and index contracts are reused unchanged.

## Compatibility and quality gates

Before 1.3 release closure:

- existing `query(BoxQuery)` source and semantic regression tests remain green;
- new `queryBuilder()` and current query APIs produce equivalent canonical query semantics where capabilities overlap;
- minimum Flutter/Dart compatibility remains validated;
- all `minimal | encryption | full` Rust profile gates remain green;
- encrypted/plaintext query/index behavior remains covered;
- cross-frontend conformance remains green;
- FRB generated binding reproducibility remains green;
- package/pub and Rust crate package readiness remain green;
- Android/iOS/macOS/Linux/Windows staged consumers remain green;
- docs, README, code walkthrough, and handoff reflect Fluent Box Query as the primary Dart authoring API only after implementation is complete.

## PR sequence

Recommended implementation sequence:

```text
1.3 PR1 — BoxQuery model + immutable Dart builder + canonical AST parity guards
1.3 PR2 — comparison/set operators + AND/OR groups + nested fields
1.3 PR3 — ordering + limit/offset + terminal get/firstOrNull
1.3 PR4 — native count/exists + typed BoxField integration + boundary evidence
1.3 PR5 — cursor pagination
1.3 PR6 — requireIndex + explain + Inspector planner diagnostics
1.3 PR7 — docs migration, benchmark evidence, release audit/version closure
```

Keep PRs narrow. Do not combine the 1.3 series with a redb major upgrade, SQL parser, reactive query subsystem, storage-format migration, or unrelated performance experiment.

## Deferred to 1.4+

The following remain conditional post-1.3 candidates:

- SQL subset frontend compiled into the same canonical Rust query representation;
- reactive query/watch semantics;
- projection/field selection where persisted encoding can avoid real decode/transfer cost;
- array query operators;
- aggregates beyond `count`;
- newer redb major-version adoption after separate compatibility, durability, and benchmark evaluation.

Candidate SQL subset, if later justified:

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

Do not position `dxtr_box` as a full SQL database and do not add JOINs, CTEs, window functions, broad DDL, or relational semantics merely for feature parity.

## Release identity

```text
1.2 — Inspector CLI / release closure
1.3 — Fluent Box Query (Phase A + Phase B)
1.4+ — evidence-driven extensions (SQL subset / reactive / projection / aggregates / dependency evolution)
```

The 1.3 product message should remain simple:

> Fluent document-oriented queries in Dart, executed by the native Rust planner.
