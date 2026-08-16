# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 claim is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot — 0.4 Production Hardening active

0.3 query/index + Hive CE migration is closed and closure-verified. PR #25 is the final 0.3 correctness closure for migration destination ownership; PR #26 synced README, handoff, and code walkthrough to that final contract.

PR #27 completed **PH-01 controlled cross-commit native-size regression policy**. The gate builds base/head commits on the same runner/toolchain and independently enforces growth budgets for `minimal`, `encryption`, and `full`.

PR #28 completed **PH-02 package / publication hardening**. `dxtr_box` is now one self-contained Flutter FFI plugin that owns:

```text
lib/
rust/
cargokit/
android/
ios/
macos/
linux/
windows/
example/
```

The Flutter package/plugin name is `dxtr_box`. The Rust crate and native library name remains `rust_lib_dxtr_box` to preserve FRB/native identity. The nested `rust_builder/` package and root path dependency are removed. Package docs, pub dry-run validation, `.pubignore`, CHANGELOG/example cleanup, and all five platform builds are part of the hardened package contract.

`flutter_rust_bridge` remains pinned to 2.8.0 because checked-in generated bindings and the runtime/codegen/macros must stay version-aligned. The pub dry-run uses `--ignore-warnings` for pub's broad-constraint advisory rather than allowing a newer incompatible FRB runtime to resolve.

**PH-03 broader Flutter local-database comparison is active in PR #29.** The initial engineering matrix compares:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

PH-03 separates a cross-engine correctness hard gate from timing diagnostics. CRUD/delete/close/reopen state equivalence is a CI requirement; sequential/batch/read/contains/delete/reopen timing is evidence only and has no faster/slower release threshold. CI emits a machine-readable JSONL artifact named `local-database-comparison`.

Normative 0.4 docs:

- `docs/PACKAGE_RELEASE_04.md`
- `docs/NATIVE_SIZE_POLICY_04.md`
- `docs/LOCAL_DATABASE_COMPARISON_04.md`

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
- Native-size absolute measurement, same-commit reproducibility, and cross-commit regression gating.
- Self-contained publishable Flutter FFI plugin topology with pub/docs validation.
- Four-engine local-database correctness + diagnostic comparison harness under `benchmark/`.

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

Current policy per profile:

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
fail when head_bytes - base_bytes > allowed_growth
```

Base and candidate commits are built from detached commit snapshots with isolated Cargo target directories under one OS/arch/rustc/cargo environment. Machine-readable evidence is written to `native-size-regression.tsv`.

The budget is a regression alarm, not a target and not a routine allowance. Intentional growth must be explained with measured profile deltas and reviewed explicitly rather than hidden by bypassing the gate.

See `docs/NATIVE_SIZE_POLICY_04.md`.

## 0.4 package/publication policy

The package distributed to consumers must be self-contained. No published dependency may rely on a repository-relative `path:` source.

Platform mapping:

```text
Android  android/build.gradle
  -> ../cargokit
  -> ../rust

iOS/macOS  {ios,macos}/dxtr_box.podspec
  -> ../cargokit/build_pod.sh
  -> ../rust

Linux/Windows  {linux,windows}/CMakeLists.txt
  -> ../cargokit/cmake/cargokit.cmake
  -> ../rust
```

Package readiness requires both publication validation and runtime/native validation:

```text
make package-readiness
  -> flutter pub get
  -> dart doc
  -> dart pub publish --dry-run --ignore-warnings

normal CI
  -> Flutter / minimum SDK / FRB / Rust / native integration / size policy

Platform Builds
  -> Android / iOS / macOS / Linux / Windows examples
```

A green pub dry-run alone is not sufficient evidence that the native plugin builds correctly.

Publication remains a separate explicit release action from a reviewed clean commit/tag.

## 0.4 local-database comparison policy

Comparison-only dependencies stay under `benchmark/`; they must not raise the root package SDK floor or become production dependencies.

Correctness hard gate:

```text
same payloads
  -> putAll
  -> overwrite
  -> contains existing/missing
  -> delete deterministic subset
  -> close/reopen
  -> verify deleted/retained records
  -> compare final snapshots across engines
```

Diagnostic matrix:

```text
sequential_put
batch_put
point_get
contains
delete_all
reopen_read
```

Each engine receives one warmup and three measured samples. Evidence records engine, scenario, operation count, raw samples, median, min, and max.

Interpretation rules:

- correctness mismatch is a release blocker;
- inability to execute the harness is a test/harness failure;
- timing differences are not pass/fail thresholds;
- hosted CI timings are diagnostic and not stable marketing benchmarks;
- performance optimization requires repeated evidence of a product-relevant bottleneck.

See `docs/LOCAL_DATABASE_COMPARISON_04.md`.

## Developer workflow

Preferred root targets:

```text
make preflight
make package-readiness
make dart-doc
make pub-dry-run
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make process-crash
make benchmark-smoke
make benchmark-comparison-correctness
make benchmark-comparison
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

### PH-01 — Cross-commit native-size regression policy — complete (PR #27)

- controlled base/head same-environment comparison;
- exactly three profiles measured;
- same-commit reproducibility retained;
- hybrid byte/percentage budget enforced;
- machine-readable evidence uploaded.

### PH-02 — Package-quality / publication hardening — complete (PR #28)

Completed acceptance:

- root `dxtr_box` is a self-contained Flutter FFI plugin;
- no nested `rust_builder` path dependency;
- native crate and Cargokit required by consumers are inside the published package;
- `dart doc` succeeds;
- pub dry-run validates the archive with the intentional exact FRB 2.8 pin documented;
- CHANGELOG/example/public library docs are current;
- CI and all five Platform Builds are green;
- README, handoff, code walkthrough, and `PACKAGE_RELEASE_04.md` agree on topology.

### PH-03 — Broader Flutter local-database comparison — active (PR #29)

Acceptance:

- at least four representative engines in the matrix, including dxtr_box and Hive CE;
- comparison dependencies remain benchmark-only;
- shared CRUD/delete/reopen correctness workload is a hard CI gate;
- timing scenarios remain diagnostic only;
- machine-readable evidence is uploaded from CI;
- no benchmark threshold drives speculative optimization;
- README, handoff, code walkthrough, and `LOCAL_DATABASE_COMPARISON_04.md` agree.

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
