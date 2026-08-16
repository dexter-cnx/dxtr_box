# dxtr_box 0.3 Closure Audit

## Purpose

This document is the release-closure checklist for the 0.3 query/index + migration milestone. It records what must be true before the milestone is considered closed and separates deferred work from 0.3 scope.

## Public API / behavior

- [x] Declarative `Box.query(BoxQuery)` exists with one native FRB call per query.
- [x] Equality, inequality, ordered comparisons, `between`, null checks, AND/OR groups, and dotted field paths are covered.
- [x] Deterministic `sortBy` runs before pagination with explicit null/missing placement and ascending record-key tie break.
- [x] Legacy `Box.where(predicate)` remains Dart-side and separate from the native query engine.
- [x] Persisted named secondary indexes support create/list/drop and transactional maintenance.
- [x] Hive CE migration is explicit and uses an already-open source adapter; the core package does not take a runtime Hive CE dependency.
- [x] Hive CE String keys are preserved; int keys default to `@hive-int:<decimal>`; conversion collisions fail before destination creation.
- [x] Unsupported/custom Hive CE values require explicit conversion.
- [x] Existing migration destinations are rejected rather than overwritten.
- [x] Concurrent migrations cannot both claim the same new destination.
- [x] Ordinary `DxtrBox.open()` is prevented from returning a usable handle while migration owns the destination reservation.
- [x] A migration-owned destination/reservation is cleaned up if `DxtrBox.open` fails during handle initialization.

## Query / index correctness

- [x] Primary `data` is authoritative; index membership only narrows candidates.
- [x] Full predicate re-evaluation occurs against primary data.
- [x] Equality and range scan/index equivalence coverage exists.
- [x] Multiple usable indexes under AND are intersected.
- [x] OR does not perform unsafe partial narrowing.
- [x] Query planner/fallback/primary reads share one redb read transaction snapshot.
- [x] Numeric comparison preserves signed/unsigned integer precision and does not collapse all integers through `f64`.
- [x] Persisted scalar MessagePack bytes are not treated as numeric redb ordering.
- [x] Deterministic sorting rejects NaN and incompatible numeric/string mixtures.

## Encryption / storage safety

- [x] Encrypted boxes can query through the authoritative native scan path.
- [x] Persisted secondary index creation on encrypted boxes is rejected.
- [x] Plaintext-to-encrypted migration is rejected while persisted indexes exist.
- [x] Reduced native profiles reject opening indexed boxes they cannot safely maintain.
- [x] Hive CE encrypted source fixtures are opened by Hive CE and migrated into encrypted dxtr_box destinations without exposing source credentials to dxtr_box.

## Native profile contract

Exactly three public native profiles remain:

```text
minimal
  CRUD + lifecycle + native watch

encryption
  minimal + encrypted create/open/read/write

full
  encryption + maintenance + query/index implementation
```

- [x] No fourth public query or migration profile exists.
- [x] FRB surface remains stable across reduced profiles with explicit unsupported-operation failures.

## Compatibility / build gates

- [x] Dart minimum remains `>=3.4.0 <4.0.0`.
- [x] Flutter minimum remains `>=3.22.0`.
- [x] Minimum SDK CI uses Flutter 3.22.0 / Dart 3.4.0.
- [x] Checked-in FRB 2.8 bindings are regenerated and drift-checked in CI.
- [x] Native Rust tests cover minimal, encryption, and full profiles on Ubuntu, macOS, and Windows.
- [x] Platform Builds cover Android, iOS, macOS, Linux, and Windows examples.
- [x] Same-commit native-size reproducibility remains a hard gate; cross-commit size budgets are not part of 0.3.

## Diagnostics / evidence

- [x] Query/index diagnostic benchmark covers equality, range, multi-index AND, and sorted-range scan vs indexed execution.
- [x] Shared-runner benchmark timing is informational, not an SLA gate.
- [x] Point-read diagnosis records `get`/`containsKey` cost without changing authoritative native semantics.
- [x] Point-read measurements do not over-attribute the native region because native MessagePack validation is included in that region.
- [x] Real Hive CE 2.19.3 fixtures cover primitive/list/map/binary/DateTime data, String/int keys, custom conversion, collision rejection, encrypted source/destination, unsupported-value preflight, source preservation, existing-destination preservation, and concurrent-destination rejection.
- [x] Root regression coverage injects a handle-initialization failure and verifies the migration-owned destination file is removed.
- [x] Root regression coverage verifies an ordinary open is rejected while migration owns the destination and works again after reservation release.

## Review follow-ups discovered during closure

Codex review `4945584625` on merged PR #23 identified two migration correctness gaps:

1. a TOCTOU race between `boxExists()` and normal `DxtrBox.open()` allowed two migrations to target the same destination;
2. if native open succeeded but watch/metadata initialization failed, the destination file could remain because the migration had not yet marked the handle as opened.

PR #24 fixed those with exclusive migration destination creation and cleanup coverage. Both original PR #23 review threads were answered and resolved.

Codex review `4945685965` on merged PR #24 then identified a remaining P1: an ordinary `DxtrBox.open(destinationName)` could still join the already-reserved destination while migration was in progress. PR #25 is the release-blocking follow-up. It adds a distinct migration reservation marker, makes normal open check that reservation both before and immediately after native open, keeps only the migration-owned internal open path eligible to bypass the marker, and adds direct regression coverage.

The second post-open check is intentional: it closes the race where a normal open started immediately before migration acquired the reservation. If migration wins destination creation, the normal native handle is closed before a `Box` is returned to application code. If normal open creates the destination first, migration's post-reservation existence check / exclusive create fails.

## Documentation closure

These files were re-read and aligned to the post-0.3 state:

- [x] `README.md`
- [x] `docs/CODE_WALKTHROUGH.md`
- [x] `docs/PROJECT_HANDOFF.md`
- [x] `docs/QUERY_INDEX_03.md`
- [x] `docs/QUERY_BENCHMARK_03.md`
- [x] `docs/POINT_READ_DIAGNOSIS_03.md`
- [x] `docs/HIVE_CE_MIGRATION_03.md`
- [x] `docs/HIVE_FUNCTIONAL_PARITY.md`

The parity audit was intentionally updated only for capabilities with implemented evidence. Remaining 1.0 gaps stay open.

## Explicitly deferred beyond 0.3

These are not blockers for 0.3 closure:

- encrypted persisted-index design;
- order-preserving scalar encoding and true scalar-level redb range seeks;
- index-backed ORDER BY;
- cross-commit native binary-size regression thresholds;
- Dart 3.13 recorded-use/native tree shaking;
- LazyBox migration;
- direct `.hive` file parsing;
- overwrite/merge migration into an existing dxtr_box destination;
- file-level crash-atomic Hive migration staging/promotion and automatic stale-reservation recovery;
- Web/IndexedDB support and 1.0 parity closure.

## Final merge evidence

PR #24 final implementation/documentation head `93e69251d5f01d613c2cc3376a3c0c1bd03c87a1` passed CI #286 (`31933799866`) and Platform Builds #196 (`31933799871`) and was squash-merged as `ff84dc1c3dc879da3ed73f79a4358659a3ea189b`. Its branch was deleted and branch API returned only `main`.

Because review `4945685965` arrived after that merge, 0.3 closure is **re-opened only for PR #25** until this final correctness follow-up has green CI, no unresolved blocker, is merged, and its branch is deleted.

Final PR #25 gate:

- [ ] current CI green on final head;
- [ ] no unresolved review threads / request-changes review;
- [ ] merge PR #25;
- [ ] delete `docs/0.3-final-evidence` after merge;
- [ ] verify branch API returns only `main`.

**0.3 status: closure pending PR #25 final correctness follow-up.**
