# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter, forged in Rust. By Dxtr.**

Target: a simple Flutter-facing local database backed by Rust/redb, with durable storage outside the Dart heap, native query/index execution, first-class encryption, and no application-level model code generation requirement.

Dxtr_Box is no longer positioned as a Hive/Hive CE replacement. Hive CE remains a useful migration source, compatibility reference, and benchmark peer, but it does not define product scope or 1.0 success.

## Product identity / key features

The intended product identity stays compact:

- Rust/redb ACID native storage;
- simple box-style asynchronous Flutter API;
- optimized authoritative point reads and one-snapshot multi-key reads;
- declarative native query engine;
- persisted secondary indexes;
- Argon2 + ChaCha20Poly1305 encryption;
- transactional bulk operations and index maintenance;
- native cross-handle watch events;
- crash/reopen durability coverage;
- explicit plaintext-to-encrypted migration;
- optional Hive CE migration tooling;
- Android/iOS/macOS/Linux/Windows native consumers;
- self-contained publishable Flutter FFI plugin topology.

Avoid expanding the product into an ORM, cloud sync service, or general schema framework unless explicitly reprioritized later.

## Current snapshot

Closed milestones:

- 0.3 query/index/migration complete.
- 0.4 Production Hardening PH-01 through PH-05 complete.
- 0.5 Performance / Read-path Optimization complete: decomposed the read path, removed the dominant single-key FRB `NormalTask` overhead, added one-snapshot `Box.getAll`, and rejected a reusable stale read-session API after investigation.
- PR #34 change-aware Fast CI / selective affected gates / full merge gate.

Current milestone:

# 0.6 — Query / Index + Encryption Hardening

0.6 intentionally combines query/index polish and encryption hardening instead of creating two broad milestones.

Normative 0.6 document: `docs/QUERY_INDEX_ENCRYPTION_06.md`.

Bounded scope:

1. query/index production polish;
2. encrypted query/index security and implementation decisions;
3. compatibility/migration improvements only when they materially improve adoption without changing the product direction.

Explicitly out of scope unless separately prioritized: ORM/code generation, cloud sync/replication, general schema framework, reactive-query redesign, and unrelated product expansion.

## Stable package/runtime contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Dart:                   >= 3.4.0 < 4.0.0
Flutter:                >= 3.22.0
flutter_rust_bridge:    2.8.0 exactly
redb:                    2.1.0
durable format:         meta[format_version] = dxtr_box/1
native profiles:        minimal | encryption | full
```

`full` is default. Do not add a fourth native profile for tuning or encrypted indexing.

Dart 3.13 recorded-use/native tree shaking remains deferred unless explicitly pulled forward.

## Current capabilities

- `DxtrBox`, `Box`, `BoxEvent` Flutter facade.
- MessagePack dynamic codec.
- One `{box}.dxtr` redb file per box.
- Transactional CRUD and bulk CRUD.
- `Box.getAll(Iterable<String>)` one-snapshot authoritative batch reads.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Explicit compact and plaintext-to-encrypted migration.
- Process crash/reopen durability coverage.
- Declarative `Box.query(BoxQuery)` with one FRB call per query.
- Persisted named scalar indexes under `full` for plaintext boxes.
- Equality/range candidate narrowing, nested indexes, AND intersection.
- One redb read snapshot per native query.
- Deterministic semantic sorting before pagination.
- Optional Hive CE 2.19.3 migration fixtures/tooling.
- Native-size baseline/stability/cross-commit regression gates.
- Self-contained publishable Flutter FFI package topology.
- Four-engine local-database comparison harness.
- Fresh staged-payload Android/iOS/macOS/Linux/Windows consumer builds.
- Public export and durable-format compatibility guards.
- Change-aware Fast CI plus full merge validation.
- Machine-readable read-path and comparison benchmark evidence.

## Hard correctness invariants

Primary `data` is authoritative; persisted indexes are derived state. Mutations keep primary and index changes in one redb write transaction and publish watch events only after commit.

`Box.get`, `Box.containsKey`, and `Box.getAll` remain authoritative native reads. Do not substitute Dart key metadata, a Dart whole-box cache, or an implicit long-lived read snapshot; those weaken cross-handle/cross-process freshness.

Encrypted reads retain full AEAD authentication. Every query result, including future encrypted-index candidates, must resolve through the authoritative primary record and complete decrypt/authenticate plus predicate re-evaluation before returning to Dart.

`dxtr_box/1` remains readable. A storage-format change requires deliberate compatibility/migration evidence, not just a marker update.

## 0.5 read-path result retained by 0.6

Single-key point reads keep the PR #35 call-mode optimization:

```text
Box.get / Box.containsKey
  -> Future-based Dart API
  -> FrbNativeDxtrApi
  -> generated FRB sync dispatch for point read only
  -> Rust authoritative redb read
  -> optional decrypt/authenticate
  -> MessagePack validation / return
```

Controlled boundary evidence recorded in 0.5:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

Batch reads remain asynchronous and use one redb snapshot/table open for the requested key set. Hosted 0.5 evidence reached ~8.59x improvement for 1,000 keys versus N independent public `get` calls.

Do not regress these paths opportunistically during 0.6.

## Query/index baseline entering 0.6

Plaintext indexes currently provide:

- named scalar index definitions;
- exact dotted-field matching;
- equality and ordered/range candidate narrowing;
- deterministic lexical index-name selection when duplicate-field indexes exist;
- multi-index AND intersection;
- authoritative primary re-read and predicate recheck;
- semantic sort before offset/limit.

Persisted indexes narrow WHERE candidates only. They do not currently satisfy ORDER BY, and raw MessagePack bytes are not treated as semantic numeric order.

## Encrypted-index safe default

Encrypted boxes currently execute query scans but reject persisted index creation in Rust:

```text
persisted indexes are not yet supported for encrypted boxes; native scan queries remain available
```

0.6 begins by turning that limitation into an explicit security contract rather than immediately removing it.

The repository must not persist plaintext scalar index bytes for encrypted boxes simply to recover plaintext-index performance.

Threat-model questions that must be answered before encrypted indexes ship include leakage of:

- indexed field names;
- record identifiers;
- equality classes / repeated values;
- ordering;
- cardinality/frequency;
- null/missing state.

Preferred first production target, if justified: equality-only keyed deterministic tokens with domain separation and full primary decrypt/authenticate + predicate recheck. Frequency/equality leakage must still be documented.

Encrypted range indexing is optional. If an acceptable representation requires excessive order leakage or complexity, encrypted range queries remain scan-only in 0.6.

A native integration regression guard requires encrypted index creation to stay blocked until that contract changes intentionally, while encrypted scan queries remain functional.

## 0.6 implementation sequence

```text
PR 1 — threat model + safe-default regression guard + milestone/product docs
PR 2 — encrypted equality index + plaintext planner/range/index polish + benchmark evidence
PR 3 — encrypted range/index decision; implementation optional, evidence-backed rejection acceptable
PR 4 — compatibility cleanup + 0.6 closure audit
```

The former PR2 and PR3 are intentionally combined. They share the same query/index execution surface and benchmark evidence, so one focused runtime PR is preferable to splitting closely coupled changes across two review cycles.

## 0.6 performance policy

Benchmarks are engineering evidence, not marketing gates.

Measure where relevant:

```text
plaintext scan vs indexed equality
plaintext scan vs indexed range
encrypted scan vs encrypted equality index (if implemented)
index create/backfill
mutation overhead with indexes
reopen/query
```

Use representative 100 / 1,000 / 10,000 record sizes where CI cost permits. Every performance claim must record methodology and correctness validation.

Do not trade security or durability for a benchmark win.

## CI topology

```text
change-detection
      |
      v
   Fast CI
      |
      +--> affected expensive validation during Draft iteration
      |
      v
Merge Gate / full quality bar
```

`make preflight` remains the cheap local gate:

```text
format-check
analyze
test-fast
contract-check
rust-check
```

Ready-for-review/non-draft work must still satisfy the full merge quality bar.

## Existing production policies that remain active

Native-size policy:

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
```

Published package must remain self-contained. Fresh staged package payloads must continue to build on Android/iOS/macOS/Linux/Windows.

Public/storage contract remains:

```text
public entrypoint: package:dxtr_box/dxtr_box.dart
storage key:       format_version
storage format:    dxtr_box/1
```

## 0.6 acceptance criteria

0.6 closes only when:

1. plaintext query/index behavior is production-polished and regression-covered;
2. encrypted query/index leakage is explicitly documented;
3. encrypted equality indexing is implemented securely or rejected with evidence;
4. encrypted range indexing is implemented under an explicit leakage contract or intentionally remains scan-only;
5. no plaintext scalar values are silently persisted for encrypted indexes;
6. authoritative primary decrypt/authenticate + predicate recheck is preserved;
7. no storage-format change occurs without backward-read/migration evidence;
8. `dxtr_box/1` remains readable;
9. exactly `minimal | encryption | full` remain the native profiles;
10. Dart >=3.4 / Flutter >=3.22 remain supported;
11. FRB remains pinned/reproducible at 2.8.0;
12. 0.5 read paths do not regress unexpectedly;
13. query/index/migration/crash-reopen tests remain green;
14. native-size policy remains green;
15. five staged platform consumers remain green;
16. README/handoff/product messaging consistently describes Dxtr_Box as its own native local database, not as a Hive replacement.

## Working style

After each merged PR:

- update `docs/PROJECT_HANDOFF.md`;
- update `docs/CODE_WALKTHROUGH.md` when architecture/execution flow changes;
- update `README.md` for material public/developer behavior changes;
- keep `docs/QUERY_INDEX_ENCRYPTION_06.md` as the normative 0.6 design/decision record;
- remove obsolete merged branches;
- keep temporary CI/debug tooling out of final branches;
- use Fast CI / affected gates during iteration and full merge validation before merge.

## Post-0.6 product maturity roadmap — Datum-inspired ideas

The following ideas are intentionally recorded as product-maturity work rather than 0.6 scope. They are inspired by useful architectural patterns seen in Datum, but Dxtr_Box should preserve its identity as a compact native embedded database rather than grow into an offline-sync framework.

Priority order:

### A. Reusable conformance / contract test kit — high priority

Create a reusable storage-contract suite that can certify Dxtr_Box behavior across public facade, native runtime, migration paths, durability scenarios, and future implementation variants.

Candidate coverage:

- CRUD and bulk-operation semantics;
- query/index semantic equivalence between scan and indexed execution;
- index maintenance invariants;
- transaction visibility and rollback behavior;
- cross-handle watch behavior;
- crash/reopen durability;
- plaintext/encrypted parity where semantics are expected to match;
- migration compatibility;
- seeded fuzz/property scenarios where practical.

This may initially remain an internal test harness. A public `dxtr_box_test` package should only be created if downstream adapter/plugin authors have a real need for it.

### B. Optional typed schema metadata — 0.7+ candidate

Investigate an optional strongly typed schema layer where one field/schema definition can drive multiple concerns instead of duplicating field metadata across APIs.

Potential uses of one metadata source:

```text
typed query fields
      +
index definitions
      +
query validation
      +
migration/schema-change detection
      +
serializer/planner hints where justified
```

Constraints:

- keep the existing dynamic box-style API first-class;
- do not require application-level model code generation;
- do not turn Dxtr_Box into an ORM;
- prefer typed field references over stringly typed field names when users opt in;
- introduce code generation only if later evidence shows that a non-codegen approach is inadequate.

A conceptual future API may resemble `UserFields.age` rather than raw `'age'` strings, but no public syntax is committed yet.

### C. Schema/config fingerprint + startup fast path — high ROI candidate

Evaluate a small persisted fingerprint for schema/index configuration so unchanged definitions can skip unnecessary reconciliation, validation, or migration work at open time.

Requirements before implementation:

- fingerprint inputs must be deterministic and explicitly versioned;
- a fingerprint match may skip redundant work but must never bypass durable-format compatibility checks or correctness validation that remains required;
- changed definitions must fall back to authoritative reconciliation;
- benchmark cold-open/reopen impact before claiming value.

This is expected to be a relatively small optimization and should be considered before building a broader schema framework.

### D. Capability-based internal architecture — investigate when multiple execution variants justify it

Consider explicit internal capabilities such as query/index/transaction/watch support when they materially simplify planner/runtime branching or future test conformance.

Do not add capability abstractions speculatively. Introduce them only when they replace meaningful runtime probing, condition scattering, or duplicated contract logic.

### E. Benchmark scenarios must remain user-facing

Continue evolving benchmarks around real operations and decisions rather than isolated microbenchmarks only.

Prefer scenarios such as:

- point read;
- multi-key read;
- scan vs indexed query;
- encrypted query cost;
- mutation cost with indexes;
- reopen/startup cost;
- migration cost;
- crash/recovery behavior where measurable.

Every benchmark result should state operation semantics, data size, runtime/platform, correctness checks, and what decision the benchmark is intended to support.

### Explicitly not adopted from Datum

Do not add these to the planned product scope without a separate product-direction decision:

- built-in cloud/offline synchronization engine;
- backend sync adapters;
- pending-operation replication queues;
- vector clocks;
- CRDT collections/text;
- generic local-first application framework behavior.

Those features operate at a different architectural layer and would materially expand Dxtr_Box beyond its current embedded-database mission.

Recommended sequencing after 0.6:

```text
1. conformance / contract test kit
2. schema/config fingerprint + startup fast path
3. optional typed schema/query metadata investigation
4. capability abstractions only where runtime complexity proves the need
```

The first three items should be evaluated as maturity improvements, not as reasons to delay stable core behavior or inflate the 1.0 definition unnecessarily.

## Deferred beyond 0.6 unless explicitly reprioritized

- Dart 3.13 recorded-use/native tree shaking;
- ORM/model code generation;
- built-in cloud replication/sync;
- general schema framework;
- index-backed ORDER BY unless measured value justifies complexity;
- LazyBox migration / direct `.hive` parsing;
- crash-atomic Hive migration staging/promotion and stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB strategy.

`docs/HIVE_FUNCTIONAL_PARITY.md` remains historical/reference material and may inform interoperability work, but it is no longer the product identity or mandatory definition of 1.0.

Do not trade correctness, durability, encryption, cross-process visibility, compatibility, or evidence quality for feature count.
