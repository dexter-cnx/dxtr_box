# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 goal is practical Hive/Hive CE local-database replacement, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

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
3. only Hive/Hive CE parity gaps necessary for practical replacement.

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
- Explicit Hive CE 2.19.3 migration fixtures.
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

A native integration regression guard now requires encrypted index creation to stay blocked until that contract changes intentionally, while encrypted scan queries remain functional.

## 0.6 implementation sequence

```text
PR 1 — threat model + safe-default regression guard + milestone docs
PR 2 — encrypted equality index implementation, only if representation is accepted
PR 3 — plaintext planner/range/index polish + measured benchmark evidence
PR 4 — encrypted range/index decision; implementation optional, evidence-backed rejection acceptable
PR 5 — required Hive parity + 0.6 closure audit
```

Small focused PRs are preferred. Do not combine all runtime changes into one review surface.

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
16. only necessary Hive/Hive CE parity gaps are pulled into scope.

## Working style

After each merged PR:

- update `docs/PROJECT_HANDOFF.md`;
- update `docs/CODE_WALKTHROUGH.md` when architecture/execution flow changes;
- update `README.md` for material public/developer behavior changes;
- keep `docs/QUERY_INDEX_ENCRYPTION_06.md` as the normative 0.6 design/decision record;
- remove obsolete merged branches;
- keep temporary CI/debug tooling out of final branches;
- use Fast CI / affected gates during iteration and full merge validation before merge.

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

Do not trade correctness, durability, encryption, cross-process visibility, compatibility, or evidence quality for feature count.
