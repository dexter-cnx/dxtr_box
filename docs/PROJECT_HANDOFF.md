# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 claim is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot — 0.4 Production Hardening active

0.3 query/index + Hive CE migration is closed and closure-verified. PR #25 is the final 0.3 correctness closure for migration destination ownership; PR #26 synced README, handoff, and code walkthrough to that final contract.

0.4 Production Hardening is now active. The first slice is **controlled cross-commit native-size regression policy**:

- preserve the three public native profiles: `minimal`, `encryption`, `full`;
- retain exact current-size measurement and same-commit reproducibility gates from 0.3;
- build the PR base SHA and candidate head SHA on the same Linux x64 runner/toolchain;
- compare each profile independently;
- fail when positive growth exceeds `max(65,536 bytes, 3% of the base artifact)`;
- emit machine-readable base/head/delta/budget evidence;
- do not use historical workflow artifacts as the comparison source because runner/toolchain drift would contaminate the signal.

Normative contract: `docs/NATIVE_SIZE_POLICY_04.md`.

## Current capabilities

- `DxtrBox`, `Box`, `BoxEvent` Flutter facade.
- Dart >= 3.4.0 / Flutter >= 3.22.0.
- MessagePack dynamic codec.
- Rust `redb = 2.1.0`, one `{box}.dxtr` file per box.
- Transactional CRUD/bulk CRUD/lifecycle.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Explicit compact and plaintext-to-encrypted migration.
- Process crash/reopen durability coverage.
- Exactly three public native profiles: `minimal`, `encryption`, `full`.
- Checked-in FRB 2.8 bindings with drift CI.
- Android/iOS/macOS/Linux/Windows example build coverage.
- Declarative `Box.query(BoxQuery)` with one FRB call per query.
- Persisted named scalar indexes under `full`.
- Equality/range planner candidate narrowing, nested indexes, and AND intersection.
- One redb read snapshot per native query.
- Deterministic semantic native sorting before pagination.
- Query/index and point-read diagnostic harnesses.
- Explicit Hive CE 2.19.3 migration fixtures in an isolated package.
- Migration reservation marker that excludes ordinary opens for the lifetime of a migration-owned destination.
- Native-size absolute measurement, same-commit reproducibility, and active 0.4 cross-commit regression gating.

## Core correctness invariants

### Storage and mutation

Primary `data` remains authoritative. Persisted indexes are derived state only.

```text
put / putAll / delete / deleteAll / clear
  -> compute index changes
  -> mutate primary data + index_entries
  -> same redb write transaction
  -> one commit
  -> watch events only after commit
```

Index create/backfill commits definition + entries atomically.

### Query execution

```text
Box.query(BoxQuery)
  -> serialize query AST
  -> one FRB call
  -> decode query once
  -> one redb ReadTransaction snapshot
  -> optional persisted-index candidate narrowing
  -> primary reads from the same snapshot
  -> decrypt if required
  -> full predicate re-evaluation
  -> deterministic semantic sort when requested
  -> record-key ascending final tie-break
  -> offset / limit
```

Persisted indexes narrow candidates only. They never replace authoritative predicate re-evaluation and do not currently satisfy ORDER BY.

Raw MessagePack scalar byte order is not treated as numeric order. Range candidate matching decodes scalar components and uses the semantic comparator.

### Encryption/index security

Encrypted boxes may use native scan queries but may not create persisted secondary indexes yet because plaintext-derived scalar keys would leak protected values. Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

Reduced profiles reject opening boxes containing persisted indexes because they cannot safely maintain derived index state.

## Hive CE migration contract

Core `dxtr_box` has no runtime dependency on Hive CE. Applications wrap an already-open Hive CE box with `HiveCeMigrationSource` and call `migrateFromHiveCe(...)`.

Preserve these invariants:

- source remains open and unmodified;
- caller opens/decrypts encrypted Hive CE sources using Hive CE itself;
- String keys are preserved;
- int keys default to `@hive-int:<decimal>`;
- custom key/value conversion is explicit;
- converted-key collisions and unsupported values fail during preflight;
- every converted value is `DxtrCodec`-preflighted before destination creation;
- migration acquires a distinct exclusive reservation marker before destination creation;
- concurrent migrations cannot both own the same target;
- ordinary `DxtrBox.open(destinationName)` checks reservation before native open and again immediately after native open;
- an in-flight ordinary open cannot escape with a usable handle if migration acquires ownership during the open;
- initialization/write failures remove migration-owned destination state and release the marker;
- successful migration closes destination and releases the marker;
- migrated entries use one `Box.putAll` / one native redb write transaction;
- hard process termination may leave an incomplete destination/reservation marker; file-level staging/promotion and automatic stale-reservation recovery remain deferred.

See `docs/HIVE_CE_MIGRATION_03.md`.

## Public native profile contract

Keep exactly these three public profiles:

```text
minimal
  CRUD + lifecycle + native watch

encryption
  minimal + encrypted create/open/read/write

full
  encryption + maintenance + query/index implementation
```

`full` remains the default production build. Do not add a fourth product profile merely to move optional code around.

## 0.4 native-size policy

0.3 established deterministic measurement first. 0.4 now permits a real cross-commit gate because base/head can be measured under one controlled environment.

Current policy per profile:

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
fail when head_bytes - base_bytes > allowed_growth
```

Comparison flow:

```text
PR base SHA
  -> detached git worktree
  -> isolated Cargo target directories
  -> minimal/encryption/full release builds

candidate head SHA
  -> current checkout
  -> isolated Cargo target directories
  -> minimal/encryption/full release builds

same OS + arch + rustc + cargo
  -> exact byte deltas
  -> policy evaluation
  -> native-size-regression.tsv
```

The budget is a regression alarm, not a target and not a routine allowance. Intentional growth must be explained with measured profile deltas and reviewed explicitly rather than hidden by bypassing the gate.

Dart 3.13 recorded-use/native tree shaking remains future-only and must not become required for correctness or raise the current SDK floor.

## Developer workflow

Preferred root targets:

```text
make preflight
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make process-crash
make benchmark-smoke
make benchmark-query-index
make diagnose-point-read
make rust-check
make native-build-minimal
make native-build-encryption
make native-size-baseline
make native-size-stability
make native-size-regression
make example-android
make example-linux
make example-windows
make example-macos
make example-ios
```

Local cross-commit examples:

```text
make native-size-regression
make native-size-regression SIZE_BASE_REF=origin/main
```

## Closed 0.3 sequence

1. Native query/index foundation.
2. Equality/range persisted-index planner with nested fields.
3. Multi-index AND candidate intersection.
4. Bounded index-name iteration.
5. One-redb-read-transaction query execution.
6. Deterministic planner selection and equivalence tests.
7. Explicit native `sortBy` contract.
8. Query/index diagnostic benchmark matrix.
9. Point-read diagnosis with authoritative native reads retained.
10. Explicit Hive CE migration with isolated Hive CE 2.19.3 fixtures.
11. Concurrent migration destination exclusion and initialization-failure cleanup.
12. Final reservation fix excluding ordinary opens before/after native open (PR #25).
13. Final documentation closure sync (PR #26).

Do not reopen 0.3 query/index/migration work for speculative optimization. Changes to those invariants require demonstrated correctness or product-performance evidence plus matching regression/equivalence coverage.

## 0.4 Production Hardening sequence

### PH-01 — Cross-commit native-size regression policy — active

Acceptance:

- base/head built in one CI environment;
- exactly three profiles compared;
- same-commit reproducibility remains a prerequisite;
- default hybrid budget enforced;
- machine-readable evidence uploaded;
- Makefile, CI, handoff, code walkthrough, and size docs agree;
- no runtime/API/storage/SDK change.

### PH-02 — Package-quality hardening — next

Audit and close package-release quality gaps, including at minimum:

- pub.dev package metadata and publish dry-run cleanliness;
- LICENSE/CHANGELOG/example/API-documentation completeness;
- exported public surface audit;
- stale/development-only files and dependency hygiene;
- repository/package versioning policy;
- CI gate for package publication readiness where practical.

Do not bump the public package to a stable 1.0 claim during this work.

### PH-03 — Broader Flutter local-database comparison — after PH-02

Expand comparison evidence beyond the current Hive CE smoke harness. Keep benchmark timings diagnostic; correctness and durability remain hard gates.

## Deferred beyond current 0.4 slice

- encrypted persisted-index design;
- order-preserving scalar encoding / scalar-level redb range seeks;
- index-backed ORDER BY;
- Dart 3.13 recorded-use/native tree shaking;
- LazyBox migration and direct `.hive` parsing;
- file-level crash-atomic Hive migration staging/promotion and stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB and remaining 1.0 Hive functional-parity gaps.

## Later roadmap

### 0.9.x

Refresh Hive Functional Parity Audit against the then-current Hive CE release and close every practical `Gap`.

### 1.0.0

- no practical parity gaps;
- stable storage/API contract;
- Web/IndexedDB strategy complete;
- pub.dev release readiness.
