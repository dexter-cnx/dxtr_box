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
- **0.6 Query / Index + Encryption Hardening** — complete after PR #43 merges with the full quality bar green.
  - PR #39 established the encrypted-index threat model and safe-default guard;
  - PR #40 added encrypted equality indexing with keyed BLAKE2b tokens plus planner polish;
  - PR #42 locked encrypted ordered/range predicates to authoritative scan-backed execution;
  - PR #43 is the final closure/audit publication of the completed milestone state.
- **Change-aware Fast CI** — complete; affected expensive gates during Draft, full merge quality bar for Ready/non-draft work.

Normative 0.6 design record: `docs/QUERY_INDEX_ENCRYPTION_06.md`.
Closure record: `docs/RELEASE_AUDIT_06.md`.

## Next milestone — 0.7 Query Ergonomics

Planned design record: `docs/QUERY_ERGONOMICS_07.md`.

The preferred next milestone is **0.7 Query Ergonomics**: improve the Dart query experience without replacing the existing query engine or changing durable storage.

Target public style:

```dart
final users = await box
    .where('status').equals('active')
    .and('age').gte(18)
    .orderBy('name')
    .limit(20)
    .find();
```

Architectural rule:

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
existing Rust planner + indexes
```

`Box.query(BoxQuery)` remains first-class for advanced/dynamic composition. The fluent API is additive, not a parallel query model.

Recommended 0.7 sequence:

```text
PR1 — fluent where/comparison/AND/OR/grouping builder
PR2 — orderBy/offset/limit/find ergonomics; native-backed convenience operations only where efficient
PR3 — optional DxtrField<T> typed field metadata; no mandatory codegen/schema
PR4 — README/examples/API equivalence/compatibility closure
```

Do not turn 0.7 into an ORM, SQL parser, schema framework, or Dart-side post-filtering layer. `exists()` / `count()` should only be exposed when backed by efficient native operations rather than materializing full result sets across FRB.

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

Do not regress these paths opportunistically during later work.

## Encrypted equality-index contract

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

## Encrypted range decision

Merged PR #42 intentionally **does not** add encrypted persisted range ordering.

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

Regression guards include `rust/tests/encrypted_range_decision.rs` and `rust/tests/encrypted_range_planner_guard.rs`.

## 0.6 closure audit

The final acceptance matrix lives in `docs/RELEASE_AUDIT_06.md`.

PR #43 is the closure publication commit. Its merge is permitted only when the repository full quality bar is green, including:

- public API/storage contract checks;
- Dart/Rust/native tests;
- query/index/encryption regression coverage;
- migration and process crash/reopen coverage;
- FRB generated-binding reproducibility;
- exact three native profiles;
- native-size regression policy;
- package/pub readiness;
- benchmark correctness/smoke;
- staged Android/iOS/macOS/Linux/Windows consumers.

The state represented by the merged closure commit is **0.6 complete**. Documentation does not bypass the quality bar; the quality bar is the condition for merging that state.

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
      +--> affected expensive validation during Draft iteration
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

## Post-0.7 maturity candidates

Datum-inspired ideas retained for later evaluation:

1. reusable conformance / storage-contract test kit;
2. schema/config fingerprint + startup fast path;
3. broader typed schema/query metadata only if `DxtrField<T>` proves valuable while keeping the dynamic box API first-class;
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
