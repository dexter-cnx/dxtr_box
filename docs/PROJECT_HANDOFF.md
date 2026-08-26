# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a compact Rust/redb local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. It is not positioned as a Hive/Hive CE replacement; Hive CE remains optional migration tooling, compatibility reference, and benchmark peer.

## Stable runtime/package contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Package version:         1.2.0
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          meta[format_version] = dxtr_box/1
native profiles:         minimal | encryption | full
```

`full` remains the default. Do not add a fourth native profile. Dart 3.13 recorded-use/native tree shaking remains deferred unless explicitly reprioritized with evidence.

## Milestone state

Completed:

- 0.3 Query / Index / Migration
- 0.4 Production Hardening
- 0.5 Performance / Read-path Optimization
- 0.6 Query / Index + Encryption Hardening
- 0.7 Query Ergonomics
- 0.8 Rust-native API / Multi-frontend Foundation
- 0.9 Conformance & Startup Maturity
- 0.10 Real-world Workload Evidence
- 1.0 Stabilization / Release Readiness
- 1.1 Post-release Evidence / Reliability
- **1.2 Inspector CLI / Release Closure**

1.0–1.2 sequence:

```text
1.0 PR1 contract-freeze audit + stronger guards                          merged (#57)
1.0 PR2 public API semantic regression inventory + tests                 merged (#61)
1.0 PR3 release-candidate consumer / migration / upgrade evidence        merged (#62)
1.0 PR4 final release audit, docs sync, version 1.0.0                    merged (#63)
post-release handoff sync                                                 merged (#64)
1.1 planning baseline                                                    merged (#65)
1.1 PR1 registry-resolved external consumer verification                 merged (#66)
1.1 PR2 native concurrency + reopen evidence                             merged (#67)
1.1 PR3 native-size / tree-shaking decision evidence                     merged (#68)
1.1 PR4 Dart isolate / FRB concurrency evidence                          merged (#69)
1.1 closure audit + docs + version 1.1.0                                 merged (#70)
1.2 Inspector CLI + release audit + docs/version synchronization         complete
```

See:

- `docs/RELEASE_AUDIT_100.md`
- `docs/ROADMAP_11.md`
- `docs/POST_RELEASE_REGISTRY_VERIFICATION_11.md`
- `docs/CONCURRENCY_EVIDENCE_11.md`
- `docs/NATIVE_SIZE_DECISION_11.md`
- `docs/DART_ISOLATE_CONCURRENCY_EVIDENCE_11.md`
- `docs/RELEASE_AUDIT_110.md`
- `docs/ROADMAP_12.md`
- `docs/INSPECTOR_CLI_12.md`
- `docs/RELEASE_AUDIT_120.md`
- `docs/FLUENT_BOX_QUERY_SPEC.md`

## Architecture

Required dependency direction:

```text
Dart API -> FRB adapter ----┐
                            ├-> shared authoritative Rust core -> redb
Rust API -------------------┘
```

The Rust frontend does not wrap Dart or FRB. GPUI is only a potential downstream consumer and is not a `dxtr_box` dependency.

One canonical storage engine means one durable contract:

```text
{box}.dxtr
meta[format_version] = dxtr_box/1
@dxtr:* durable MessagePack tags where already defined
```

Primary records are authoritative. Persisted indexes are derived state maintained transactionally with primary mutations.

## Public frontends

Dart consumers use `Box`, `BoxStore`, current query builders, and optional authoring metadata `BoxField<T>`. `DxtrBox` remains only as a deprecated source-compatibility shim where required.

Native Rust consumers use `DxtrBox`, `BoxHandle`, `Record`, `IndexDefinition`, `DxtrBoxError`, and full-profile query types. The Rust API is synchronous and has no Tokio commitment.

Both frontends converge onto the same canonical query representation, planner, redb storage path, encryption path, and persisted indexes.

The planned **Fluent Box Query API** must preserve that architecture: it is a primary Dart authoring surface over the existing canonical Rust query semantics, not a new Dart-side query engine.

## Stable evidence baseline

The stable line is guarded by executable evidence rather than documentation-only claims:

- exact Dart export and Rust root/wildcard contract guards;
- query model and fluent-builder semantic regression tests;
- native persistence and reopen coverage;
- encrypted reopen and wrong/missing-key rejection;
- Hive CE migration destination reservation/lifecycle coverage;
- staged published payload validation;
- generated consumer builds on Android, iOS, macOS, Linux, and Windows;
- FRB generated binding reproducibility;
- exact `minimal | encryption | full` Rust profile testing;
- native-size regression policy plus reproducible Linux/macOS evaluation evidence;
- guaranteed native concurrent reader/writer overlap and durable reopen;
- independent Dart isolate / FRB shared-storage visibility and close/reopen durability;
- read-only Inspector CLI semantic/encrypted/raw inspection evidence;
- package docs + pub dry-run;
- benchmark correctness and diagnostic smoke;
- startup/reopen, multi-frontend, and real-world workload diagnostics.

The durable format remains `dxtr_box/1`; 1.2 introduced no storage migration.

## Current performance interpretation

Current diagnostics indicate that very small Flutter/Dart point reads are dominated primarily by Dart async + FRB boundary cost rather than redb lookup cost.

Representative controlled evidence has shown:

- Rust-native point reads in the low-microsecond/sub-microsecond class on the benchmark runner;
- substantially higher public Dart/FRB point-read latency because fixed boundary overhead dominates tiny operations;
- much narrower gaps for `getAll` and indexed query/sort/limit workloads because more work is amortized per native call;
- reopen p95 below 1 ms in the tested hosted Linux startup matrix.

Performance policy:

1. Preserve correctness and storage semantics before chasing microbenchmarks.
2. Prefer batching and query pushdown over repeated Dart <-> Rust crossings.
3. Keep builder composition local to Dart; execute only terminal operations across FRB.
4. Do not introduce a whole-box Dart cache merely to win point-read benchmarks.
5. Track future FRB improvements because lower boundary overhead should benefit the Dart frontend without requiring a storage-engine redesign.
6. Further redb micro-optimization is lower priority unless profiling shows the Rust core has become dominant.

## CI / local preflight

Before push:

```bash
make preflight
```

Tracked formatting guard installation:

```bash
bash tool/install_git_hooks.sh
```

Full merge validation retains format/analyze/tests, minimum SDK, all three Rust profiles, native integration, migration/query/index/crash-reopen regression, FRB generation reproducibility, native-size policy, package/pub readiness, benchmark correctness, and staged Android/iOS/macOS/Linux/Windows consumers.

## Preserved non-goals

Do not turn post-1.2 work into:

- GPUI integration inside core;
- Tokio/runtime commitment;
- ORM/schema/model code generation;
- cloud sync/CRDT/network database functionality;
- storage-format redesign without an explicit migration plan;
- a second query engine in Dart;
- encryption redesign;
- a fourth native profile;
- full Firebase/Firestore compatibility;
- full SQL compatibility merely for feature count.

## Planned primary query evolution: Fluent Box Query API

Detailed design: `docs/FLUENT_BOX_QUERY_SPEC.md`.

### Product direction

Make **Fluent Box Query API** the documented primary Dart query experience while keeping `dxtr_box` terminology and identity.

Recommended naming:

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

Do not use Firebase or Firestore naming in the public API or product positioning.

Desired Dart experience:

```dart
final users = await box
    .query()
    .where('status', isEqualTo: 'active')
    .where('profile.age', isGreaterThanOrEqualTo: 18)
    .orderBy('lastSeenAt', descending: true)
    .limit(50)
    .get();
```

This syntax is intentionally document-oriented, but the implementation remains native Rust query execution.

### Architectural rule

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

No frontend gets a separate planner or storage semantics.

### Phase A — primary fluent surface

Implement only after the current 1.2 release line is stable and the work can be isolated behind compatibility tests.

Scope:

- `query()` entry point;
- immutable Dart `BoxQuery` builder;
- nested dotted field paths;
- `==`, `!=`, `<`, `<=`, `>`, `>=`;
- `whereIn` / `whereNotIn`;
- explicit AND/OR grouping without ambiguous precedence;
- deterministic `orderBy` with record-key tie-breaking;
- `limit` / `offset`;
- terminal `get`, `firstOrNull`, `count`, `exists`;
- optional `BoxField<T>` integration;
- one-call FRB terminal execution;
- canonical Rust planner reuse;
- semantic parity tests against the current query path;
- benchmark checks proving builder composition adds no extra FRB crossings.

Compatibility rule for Phase A:

```text
existing query API + BoxQuery API
```

Do not delete or immediately deprecate the current public query API.

### Phase B — production query ergonomics

After Phase A semantics are stable:

- cursor pagination: `startAt`, `startAfter`, `endAt`, `endBefore`;
- `requireIndex()` for applications that want to reject accidental full scans;
- `explain()` returning structured planner/index diagnostics;
- Inspector CLI reuse of planner explain information where practical;
- same-run scan-vs-index and Dart/FRB-vs-native benchmark evidence.

### Phase C — conditional extensions

Only with concrete consumer demand and executable evidence:

- array operators;
- projection/field selection when the persisted encoding can actually avoid unnecessary decode/transfer cost;
- reactive query watching with explicit invalidation/order/isolate semantics;
- aggregates beyond `count`;
- SQL subset frontend.

### Future SQL subset policy

SQL is potentially useful as a convenience frontend, not as a replacement identity or second database engine.

Candidate initial subset:

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

If implemented, SQL must parse/compile into the same canonical Rust query representation used by Dart and Rust fluent APIs.

Do not initially implement JOINs, CTEs, window functions, broad DDL, or full relational semantics.

## Query performance rules

The Fluent Box Query work is partly a developer-experience improvement and partly a boundary-efficiency strategy.

Required rules:

1. `.where()`, `.orderBy()`, `.limit()`, grouping, and cursor construction happen entirely in Dart memory.
2. One terminal operation normally equals one native execution request.
3. Filtering, sorting, index selection, `count`, and `exists` execute in Rust.
4. `count()` must not fetch every matching value into Dart just to call `.length`.
5. `exists()` should stop at the first authoritative match.
6. Indexes remain planner optimizations; result semantics must remain correct without them unless `.requireIndex()` is requested.
7. Encrypted equality/range behavior must reuse existing encryption/index contracts rather than inventing special query syntax.

## Immediate post-1.2 priority order

1. Keep 1.2 publication/registry verification and existing reliability gates authoritative.
2. Continue evidence-driven FRB read-boundary investigation when changes in FRB/toolchain or consumer workloads justify it.
3. Evaluate Fluent Box Query Phase A as the next substantial query DX change, starting with API/AST compatibility tests before implementation.
4. Do not mix Fluent Box Query implementation with redb major-version migration, SQL syntax, reactive queries, or storage-format changes in one PR series.
5. Evaluate newer redb releases separately with compatibility + durability + benchmark evidence before any dependency-major upgrade.
6. Keep README, code walkthrough, handoff, and benchmark interpretation synchronized whenever the primary query API changes.

## Compatibility rule

Treat the Dart public API, Rust root API, package identities, native profiles, and `dxtr_box/1` durable format as compatibility-sensitive contracts. Breaking changes require an explicit versioning/migration decision rather than incidental refactoring.

Correctness, durability, authenticated encryption, cross-process/cross-frontend visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.