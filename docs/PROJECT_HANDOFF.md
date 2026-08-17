# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 goal is practical Hive/Hive CE local-database replacement, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot

Closed milestones:

- 0.3 query/index/migration complete.
- 0.4 Production Hardening PH-01 through PH-05 complete.
- PR #27 native-size regression policy.
- PR #28 package/publication hardening.
- PR #29 four-engine correctness + diagnostic comparison.
- PR #30 staged published-payload five-platform consumer validation.
- PR #31 public API + durable-storage contract guard.
- PR #34 change-aware Fast CI / selective affected gates / full merge gate.
- PR #33 0.5 PR1 read-path decomposition and corrected benchmark baseline.
- PR #35 0.5 PR2 single-key cross-runtime read optimization merged.
- PR #36 0.5 PR3 one-snapshot batch/multi-key reads merged.

Current 0.5 sequence:

```text
PR 1 / #33 — read-path decomposition + corrected evidence baseline   complete / merged
PR 2 / #35 — sync FRB point-read boundary for get / containsKey      complete / merged
PR 3 / #36 — one-snapshot batch / multi-key reads                     complete / merged
PR 4 / #37 — read-session investigation                               decision complete / validation
PR 5       — comparison matrix + 0.5 closure audit                    next
```

Normative performance document: `docs/PERFORMANCE_READ_PATH_05.md`.
Normative read-session decision: `docs/READ_SESSION_INVESTIGATION_05.md`.
Normative CI document: `docs/CI_STRATEGY.md`.

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

`full` is default. Do not add a fourth native profile for performance tuning.

Dart 3.13 recorded-use/native tree shaking remains deferred outside current 0.5 work unless explicitly pulled forward.

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
- Persisted named scalar indexes under `full`.
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
- Machine-readable read-path benchmark evidence.

## Hard correctness invariants

Primary `data` is authoritative; persisted indexes are derived state. Mutations keep primary and index changes in one redb write transaction and publish watch events only after commit.

`Box.get`, `Box.containsKey`, and `Box.getAll` remain authoritative native reads. Do not substitute Dart key metadata, a Dart whole-box cache, or an implicit long-lived read snapshot; those would weaken cross-handle/cross-process freshness.

Encrypted reads retain full AEAD authentication. Query/index/migration behavior and `dxtr_box/1` compatibility remain hard gates.

## Point-read path after PR #35

```text
Box.get / Box.containsKey
  -> Future-based NativeDxtrApi
  -> FrbNativeDxtrApi
  -> generated FRB sync call for point read only
  -> Rust api::get / api::contains_key
  -> redb authoritative read
  -> optional decrypt/authenticate
  -> MessagePack validation / payload return
  -> Dart decode where applicable
```

Only Rust `get` and `contains_key` use `#[frb(sync)]`. Query, batch reads, scans, mutations, migrations, and other potentially heavier operations remain asynchronous.

PR2 controlled boundary evidence:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

## Batch-read path after PR #36

Public API:

```dart
Future<List<MapEntry<String, dynamic>>> Box.getAll(
  Iterable<String> keys,
)
```

Execution:

```text
N keys
  -> Box.getAll
  -> NativeBatchReadApi
  -> FrbNativeDxtrApi.getAll
  -> one asynchronous generated FRB call
  -> Rust api::get_all
  -> db::get_all
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative lookups
  -> decrypt/authenticate + MessagePack validation for every hit
  -> one response
  -> Dart decode
```

Semantics:

- hits preserve requested order;
- missing keys are omitted;
- duplicate input keys produce duplicate result entries;
- empty input returns empty without crossing native;
- every key is validated before native dispatch;
- encrypted hits retain full AEAD authentication;
- FRB batch dispatch remains asynchronous.

PR3 hosted evidence from Read-path Benchmark #31:

| Keys | `getAll` batch | N independent `get` calls | Improvement |
|---:|---:|---:|---:|
| 10 | 445 us | 636 us | ~1.43x |
| 100 | 814 us | 5,256 us | ~6.46x |
| 1,000 | 3,729 us | 32,032 us | ~8.59x |

PR #36 merged as `392bdf6e0af3741133eb4fb28b0638f4ecbd5a32` after full Merge Gate success.

## PR4 read-session decision

PR4 investigated a reusable native/redb snapshot across multiple Dart calls. **Decision: do not add a production read-session API in 0.5.**

Reasons:

1. redb read transactions capture a fixed snapshot at `begin_read()`. A reusable session is therefore intentionally stale after later commits.
2. Ordinary `get` / `containsKey` / `getAll` have established authoritative fresh-per-call semantics and must not silently inherit a stale snapshot.
3. PR1 measured transaction + table-open at roughly 0.567 us for the representative medium plaintext workload; this is no longer the dominant point-read cost after PR2.
4. PR3 already gives callers with known key sets one Dart/FRB crossing + one redb snapshot through `getAll`.
5. A cross-call session would require explicit close/leak/box-close/compact/migration/multi-handle lifecycle semantics and a native registry or equivalent ownership model.
6. The project is pinned to redb 2.1.0; upstream 2.1.1 specifically fixed a panic involving `compact()` while a read transaction is in progress. Intentionally lengthening read-transaction lifetimes is therefore a poor fit for the current pinned dependency.

This is an evidence-backed rejection, not a permanent ban. Reconsider only for a concrete product requirement for coherent snapshot semantics across separate logical calls, with explicit stale-within-session behavior and new benchmark/lifecycle evidence.

Detailed record: `docs/READ_SESSION_INVESTIGATION_05.md`.

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

`make preflight` mirrors the cheap gate:

```text
format-check
analyze
test-fast
contract-check
rust-check
```

Ready-for-review/non-draft work must still satisfy the full merge quality bar.

## Next — PR5 comparison matrix + 0.5 closure audit

PR5 should:

- rerun the final comparison matrix with current 0.5 APIs where applicable;
- preserve correctness-first interpretation of benchmark results;
- verify Dart >=3.4 / Flutter >=3.22;
- verify FRB 2.8.0 drift protection;
- verify exactly three native profiles;
- verify `dxtr_box/1` readability;
- verify query/index/migration regressions;
- verify native-size policy;
- verify staged published consumers on Android/iOS/macOS/Linux/Windows;
- close 0.5 only if all hard gates remain green.

Do not reopen read-session implementation inside PR5 unless new evidence changes the PR4 decision.

## Existing 0.4 policies that remain active

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

## 0.5 acceptance criteria

0.5 is not complete yet. Before closure require:

1. Evidence-backed bottleneck decomposition — satisfied.
2. At least one production read-path optimization — satisfied by PR #35.
3. `get` / `containsKey` improvement — satisfied by PR #35 evidence.
4. Efficient multi-key support or evidence-based rejection — satisfied by PR #36.
5. No Dart whole-box cache — preserved.
6. No durability/cross-process regression — preserved.
7. No encryption/authentication weakening — preserved.
8. `dxtr_box/1` remains readable — preserved.
9. Exactly three native profiles remain — preserved.
10. Dart >=3.4 / Flutter >=3.22 remain supported — preserved.
11. FRB remains pinned/reproducible at 2.8.0 — preserved.
12. Query/index/migration stays green — required at final merge gate.
13. Native-size gate stays green — required at final merge gate.
14. Five-platform staged consumers stay green — required at final merge gate.
15. Read-session decision — satisfied by PR #37 rejection record, pending PR merge.
16. Comparison/closure audit — pending PR5.

## Working style

Use small focused branches/PRs. After each merged PR:

- update `docs/PROJECT_HANDOFF.md`;
- update `docs/CODE_WALKTHROUGH.md` when architecture/execution flow changes;
- update performance evidence when relevant;
- update README only for material public/developer behavior changes;
- remove obsolete merged branches;
- keep temporary CI/debug tooling out of final branches;
- prefer Fast CI / affected gates during iteration and full merge validation before merge.

## Deferred beyond current slice

- Dart 3.13 recorded-use/native tree shaking;
- encrypted persisted-index design;
- order-preserving scalar encoding / scalar-level redb range seeks;
- index-backed ORDER BY;
- LazyBox migration / direct `.hive` parsing;
- crash-atomic Hive migration staging/promotion and stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB and remaining 1.0 Hive functional-parity gaps.

Do not trade correctness, durability, encryption, cross-process visibility, compatibility, or evidence quality for benchmark numbers.
