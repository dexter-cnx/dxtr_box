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
- PR #35 0.5 PR2 single-key cross-runtime read optimization validated and ready to merge.

Current 0.5 sequence:

```text
PR 1 / #33 — read-path decomposition + corrected evidence baseline   complete
PR 2 / #35 — sync FRB point-read boundary for get / containsKey      complete / ready to merge
PR 3       — batch/multi-key read path                                next
PR 4       — read-session investigation                              planned
PR 5       — comparison matrix + 0.5 closure audit                   planned
```

Normative performance document: `docs/PERFORMANCE_READ_PATH_05.md`.
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

`Box.get` and `Box.containsKey` remain authoritative native reads. Do not substitute Dart key metadata or a Dart whole-box cache; that would weaken cross-handle/cross-process freshness.

Encrypted reads retain full AEAD authentication. Query/index/migration behavior and `dxtr_box/1` compatibility remain hard gates.

## Point-read path after PR #35

Public API shape is unchanged:

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

Only Rust `get` and `contains_key` use `#[frb(sync)]`.

Query, scan, mutation, migration and other potentially heavier operations remain on their existing asynchronous call modes. No cache or stale long-lived read snapshot was introduced.

## 0.5 PR1 baseline

Corrected PR1 evidence came from Read-path Benchmark #11, run `31949461503`.

Representative medium medians:

```text
Rust db_get plaintext hit        ~1.055 us
Rust db_contains_key hit         ~0.655 us
Dart native-adapter get          ~90.470 us
public Box.get                  ~102.118 us
Dart native containsKey          ~74.310 us
public Box.containsKey           ~74.672 us
```

The corrected public-wire workload showed native validation/copy/transaction costs were small relative to the cross-runtime gap.

## 0.5 PR2 boundary diagnosis and implementation

The controlled boundary benchmark isolated the generated FRB call mode as the dominant single-key overhead.

Pre-change representative values:

```text
generated FRB get via NormalTask          ~226 us/op
generated FRB containsKey via NormalTask  ~197 us/op
native db_get plaintext hit               ~0.66 us/op
native db_contains_key hit                ~0.48 us/op
```

Production optimization:

```rust
#[frb(sync)]
pub fn get(...)

#[frb(sync)]
pub fn contains_key(...)
```

Checked-in bindings were regenerated with flutter_rust_bridge_codegen 2.8.0.

Post-change Read-path Benchmark #24, run `31954326856`, recorded:

```text
generated FRB get sync hit           4.312 us/op
generated FRB get sync miss          1.888 us/op
generated FRB containsKey sync hit   2.570 us/op
generated FRB containsKey sync miss  1.734 us/op
native adapter get async hit        21.076 us/op
native adapter contains async hit   17.636 us/op
```

Direct generated-FRB point-read latency improved by approximately 52x for `get` and 77x for `containsKey` versus the controlled pre-change boundary run. Hosted-runner timings are diagnostic, not release-performance guarantees.

## PR #35 validation

Full CI rerun `31954326887` reached a green `Merge Gate / full quality bar`.

Validated successfully:

- Fast CI.
- Dart full tests.
- Rust minimal/encryption/full profiles.
- Rust cross-platform checks.
- Native integration.
- Storage/migration/query regression.
- FRB generated-binding drift check.
- Package/docs + pub dry-run.
- Minimum Flutter 3.22.0 / Dart 3.4.0 compatibility.
- Native-size policy.
- Benchmark correctness/diagnostic smoke.
- staged Android/iOS/macOS/Linux/Windows consumers.

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

## Next — PR3 batch/multi-key reads

Preferred design:

```text
N keys
  -> one public/native batch API
  -> one FRB call
  -> one redb read transaction/snapshot
  -> N authoritative lookups
  -> optional decrypt/authenticate per hit
  -> one response
```

Requirements:

- define missing-key behavior explicitly;
- define duplicate-key behavior explicitly;
- support encrypted boxes;
- preserve input-order or document another deterministic result order;
- add Dart/Rust/native integration coverage;
- benchmark 10 / 100 / 1,000 keys;
- compare against N independent `get` calls;
- do not expose benchmark-only production APIs.

## PR4 read-session investigation

Evaluate redb transaction lifetime, writer interaction, stale snapshots, resource retention, Flutter lifecycle, multi-handle behavior and cross-process expectations.

Do not silently move ordinary `get` onto a long-lived stale snapshot. If reusable sessions are justified, prefer explicit session semantics. Document the decision even if the outcome is “do not implement.”

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
4. Efficient multi-key support or evidence-based rejection — pending PR3.
5. No Dart whole-box cache — preserved.
6. No durability/cross-process regression — preserved.
7. No encryption/authentication weakening — preserved.
8. `dxtr_box/1` remains readable — preserved.
9. Exactly three native profiles remain — preserved.
10. Dart >=3.4 / Flutter >=3.22 remain supported — validated.
11. FRB remains pinned/reproducible at 2.8.0 — validated.
12. Query/index/migration stays green — validated.
13. Native-size gate stays green — validated.
14. Five-platform staged consumers stay green — validated.
15. Comparison/closure audit — pending PR5.

## Working style

Use small focused branches/PRs. After each merged PR:

- update `docs/PROJECT_HANDOFF.md`;
- update `docs/CODE_WALKTHROUGH.md`;
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

Do not trade correctness, durability, encryption, cross-process visibility, compatibility or evidence quality for benchmark numbers.