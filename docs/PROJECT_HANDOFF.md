# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter, forged in Rust. By Dxtr.**

Dxtr_Box is a compact Flutter-facing local database backed by Rust/redb, with durable native storage, declarative query/index execution, first-class authenticated encryption, and simple box-style ergonomics.

It is **not** positioned as a Hive/Hive CE replacement. Hive CE remains an optional migration source, compatibility reference, and benchmark peer; it does not define product scope or 1.0 success.

## Stable runtime/package contract

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

`full` remains the default. Do not add a fourth native profile. Dart 3.13 recorded-use/native tree shaking remains deferred unless explicitly reprioritized.

## Closed milestones

- **0.3 Query / Index / Migration** — complete.
- **0.4 Production Hardening PH-01..PH-05** — complete.
- **0.5 Performance / Read-path Optimization** — complete.
  - decomposed point-read cost;
  - changed tiny `get` / `contains_key` FRB entrypoints to generated sync dispatch while preserving async public Dart API;
  - added one-snapshot `Box.getAll`;
  - rejected reusable long-lived read sessions because redb read transactions are fixed snapshots and can become stale;
  - final comparison/closure audit merged.
- **Change-aware Fast CI** — complete; affected expensive gates during Draft, full merge quality bar for Ready/non-draft work.

## Current milestone — 0.6 Query / Index + Encryption Hardening

Normative design/acceptance record: `docs/QUERY_INDEX_ENCRYPTION_06.md`.

Current PR sequence:

```text
PR1 — threat model + safe-default regression guard + milestone/product docs: merged (#39)
PR2 — encrypted equality index + plaintext planner/range/index polish: merged (#40)
PR3 — encrypted range/index decision: active (#42)
PR4 — core reliability/API closure + 0.6 audit: final
```

PR4 is not a Hive/Hive CE parity pass.

## Current capabilities

- Rust/redb ACID storage, one `{box}.dxtr` file per box.
- MessagePack dynamic values.
- Transactional CRUD and bulk CRUD.
- Authoritative `get`, `containsKey`, and one-snapshot `getAll` reads.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Explicit plaintext-to-encrypted migration.
- Process crash/reopen durability coverage.
- Declarative `Box.query(BoxQuery)` with one native query call.
- Plaintext persisted scalar indexes: equality, range, nested fields, deterministic selection, AND intersection.
- Encrypted persisted equality indexes under `full` using deterministic keyed BLAKE2b MAC tokens.
- Encrypted ordered/range predicates remain scan-backed.
- Deterministic semantic sorting before pagination; indexes currently narrow `where` only and do not satisfy ORDER BY.
- Self-contained publishable Flutter FFI plugin topology.
- Android/iOS/macOS/Linux/Windows staged consumer validation.
- Native-size baseline/stability/cross-commit regression policy.
- Four-engine local-database comparison harness plus read/query diagnostics.

## Hard correctness invariants

Primary `data` is authoritative. Persisted indexes are derived state.

Mutations keep primary data and index maintenance in the same redb write transaction; watch events publish only after commit.

Do not replace authoritative native reads with Dart metadata, a Dart whole-box cache, or an implicit long-lived read snapshot.

Encrypted reads always retain full AEAD authentication. Every encrypted-index candidate must:

```text
candidate key
  -> authoritative primary record
  -> ChaCha20Poly1305 authenticate/decrypt
  -> full predicate re-evaluation
  -> sort / offset / limit
  -> Dart result
```

Encrypted index entries must never contain raw plaintext scalar bytes.

`dxtr_box/1` remains readable. Any storage-format change requires deliberate backward-read/migration evidence.

## 0.5 read-path evidence retained

Controlled boundary evidence from 0.5:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

`Box.getAll` uses one native crossing and one redb read snapshot; hosted evidence reached about 8.59x improvement for 1,000 keys versus independent public `get` calls.

Do not regress these paths opportunistically during 0.6.

## PR2 encrypted equality-index contract

Merged PR #40 introduced encrypted equality candidate narrowing:

```text
encrypted equality query
  -> query scalar canonicalization
  -> BLAKE2b keyed MAC token
     domain separated by index name + field
  -> exact token candidate lookup
  -> authoritative primary read
  -> authenticate/decrypt
  -> full predicate recheck
```

Accepted leakage:

- index/field names;
- candidate record identifiers;
- equality classes/frequency for repeated values;
- approximate indexed cardinality.

Not intentionally persisted:

- plaintext scalar values;
- semantic scalar ordering.

An earlier BLAKE3 implementation exceeded native-size policy and was replaced by BLAKE2 reuse already present through Argon2. Final measured full-profile Linux x64 evidence for PR2 was +30,432 bytes / +1.276%, within policy.

## PR3 encrypted range decision

PR3 intentionally **does not** add encrypted persisted range ordering.

Production contract for encrypted boxes:

```text
Equal                  -> keyed equality index may narrow candidates
GreaterThan            -> authoritative scan
GreaterThanOrEqual     -> authoritative scan
LessThan               -> authoritative scan
LessThanOrEqual        -> authoritative scan
Between                -> authoritative scan
```

For mixed `AND`, equality terms may narrow candidates; ordered/range terms are evaluated after authoritative decrypt/authenticate.

Rejected for 0.6:

- sorting keyed hash/MAC bytes;
- plaintext/reversible sortable index bytes;
- order-preserving/order-revealing encryption;
- bucketized range tokens.

Reason: either incorrect ordering semantics, unacceptable order/distribution leakage, or complexity/storage/versioning cost disproportionate to current product value.

Decision record: `docs/ENCRYPTED_RANGE_DECISION_06.md`.

PR3 regression guard: `rust/tests/encrypted_range_decision.rs` covers all five ordered/range operators plus mixed equality+range `AND` before/after encrypted index creation.

## Benchmark policy

Benchmarks are engineering evidence, not marketing gates.

Important diagnostic targets:

```bash
make benchmark-comparison
make benchmark-query-index
make diagnose-point-read
make benchmark-read-path
make benchmark-batch-read
```

Hosted-runner timings are non-gating. Do not publish timing claims without the corresponding benchmark run, methodology, dataset size, and correctness validation.

## CI topology

```text
change detection
      |
      v
   Fast CI
      |
      +--> affected expensive gates during Draft iteration
      |
      v
Merge Gate / full quality bar
```

Cheap local preflight:

```bash
make preflight
```

Full merge validation must preserve:

- minimum Flutter/Dart compatibility;
- Dart/Rust/native tests;
- exact three native profiles;
- migration/query/crash-reopen regression;
- FRB generated-binding reproducibility;
- native-size policy;
- package/pub readiness;
- staged Android/iOS/macOS/Linux/Windows consumers.

## PR4 target

After PR3 merges, PR4 should be the final **core reliability/API closure + 0.6 audit**.

Only pull in cleanup that independently strengthens Dxtr_Box itself. Avoid feature expansion.

PR4 should verify the 0.6 acceptance matrix, synchronize public/internal docs, record release evidence, and close the milestone.

## Post-0.6 maturity candidates

Datum-inspired ideas retained for later evaluation:

1. reusable conformance / storage-contract test kit;
2. schema/config fingerprint + startup fast path;
3. optional typed schema/query metadata while keeping the dynamic box API first-class;
4. capability abstractions only when multiple execution variants justify them;
5. user-facing benchmark scenarios rather than isolated microbenchmarks only.

Explicitly not adopted without a separate product-direction decision:

- built-in cloud/offline synchronization;
- backend sync adapters;
- pending-operation replication queues;
- vector clocks;
- CRDT collections/text;
- generic local-first application framework behavior.

## Deferred unless explicitly reprioritized

- Dart 3.13 recorded-use/native tree shaking;
- ORM/model code generation;
- built-in cloud replication/sync;
- general schema framework;
- index-backed ORDER BY unless evidence justifies complexity;
- LazyBox/direct `.hive` parsing;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB strategy.

## Working rule

Correctness, durability, authenticated encryption, cross-process visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.
