# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 claim is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot — 0.4 Production Hardening active

Closed milestones:

- PR #25 final 0.3 Hive CE migration destination-ownership correctness.
- PR #26 final 0.3 documentation closure.
- PR #27 PH-01 controlled cross-commit native-size regression policy.
- PR #28 PH-02 self-contained package/publication hardening.
- PR #29 PH-03 broader Flutter local-database correctness + diagnostic comparison.

**PH-04 published-payload consumer validation is active.** The remaining package-evidence gap is that `dart pub publish --dry-run` validates metadata and intended files while prior Platform Builds consumed the repository checkout directly. PH-04 stages the publication boundary and builds fresh consumer applications from that staged package copy on all five native targets.

Normative 0.4 docs:

- `docs/PACKAGE_RELEASE_04.md`
- `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md`
- `docs/NATIVE_SIZE_POLICY_04.md`
- `docs/LOCAL_DATABASE_COMPARISON_04.md`

## Stable package/runtime contract

`dxtr_box` is one self-contained Flutter FFI plugin:

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

The Flutter package/plugin identity is `dxtr_box`; the Rust crate/native library remains `rust_lib_dxtr_box` to preserve FRB/native identity.

Compatibility remains:

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
```

FRB is intentionally pinned exactly because checked-in generated bindings, Dart runtime, Rust runtime, codegen, and macros must remain version-aligned. Pub validation uses `--ignore-warnings` for the broad-constraint advisory rather than allowing an incompatible newer FRB runtime to resolve.

## Current capabilities

- `DxtrBox`, `Box`, `BoxEvent` Flutter facade.
- MessagePack dynamic codec.
- One `{box}.dxtr` file per box.
- Transactional CRUD/bulk CRUD/lifecycle.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Explicit compact and plaintext-to-encrypted migration.
- Process crash/reopen durability coverage.
- Exactly three public native profiles: `minimal`, `encryption`, `full`.
- Checked-in FRB 2.8 bindings with drift CI.
- Android/iOS/macOS/Linux/Windows native build coverage.
- Declarative `Box.query(BoxQuery)` with one FRB call per query.
- Persisted named scalar indexes under `full`.
- Equality/range planner candidate narrowing, nested indexes, and AND intersection.
- One redb read snapshot per native query.
- Deterministic semantic native sorting before pagination.
- Explicit Hive CE 2.19.3 migration fixtures in an isolated package.
- Migration reservation marker excluding ordinary opens during migration ownership.
- Native-size absolute measurement, same-commit reproducibility, and cross-commit regression gating.
- Self-contained publishable Flutter FFI package topology with docs/pub validation.
- Four-engine local-database correctness + diagnostic comparison harness.

## Core correctness invariants

### Storage and mutation

Primary `data` is authoritative; persisted indexes are derived state.

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
  -> decode once
  -> one redb ReadTransaction snapshot
  -> optional persisted-index candidate narrowing
  -> authoritative primary reads from same snapshot
  -> decrypt if required
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> record-key ascending final tie-break
  -> offset / limit
```

Persisted indexes narrow candidates only; they do not replace predicate re-evaluation and do not currently satisfy ORDER BY. Raw MessagePack scalar byte order is not treated as numeric order.

### Encryption/index safety

Encrypted boxes may use scan queries but may not create persisted secondary indexes because plaintext-derived scalar keys would leak protected values. Plaintext-to-encrypted migration is rejected while persisted index definitions exist. Reduced native profiles reject boxes containing persisted indexes because they cannot safely maintain derived state.

## Hive CE migration contract

Core `dxtr_box` has no runtime dependency on Hive CE. Applications wrap an already-open Hive CE box with `HiveCeMigrationSource` and call `migrateFromHiveCe(...)`.

Preserve:

- source open/unmodified;
- String keys preserved;
- int keys default to `@hive-int:<decimal>`;
- custom conversion explicit;
- converted-key collisions/unsupported values fail in preflight;
- `DxtrCodec` preflight before destination creation;
- exclusive migration reservation before destination creation;
- concurrent migration and ordinary-open exclusion;
- failure cleanup removes migration-owned destination and reservation;
- one destination `putAll` / one native redb write transaction;
- hard-kill stale destination/reservation recovery remains deferred.

See `docs/HIVE_CE_MIGRATION_03.md`.

## Public native profiles

Keep exactly:

```text
minimal     CRUD + lifecycle + native watch
encryption  minimal + encrypted create/open/read/write
full        encryption + maintenance + query/index implementation
```

`full` is default. Do not add a fourth public profile for size tuning.

## 0.4 native-size policy

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
fail when head_bytes - base_bytes > allowed_growth
```

Base/head are detached committed snapshots built under one OS/arch/rustc/cargo environment with isolated target dirs. Evidence is `native-size-regression.tsv`. Intentional growth must be reviewed with measured deltas rather than hidden by bypassing the gate.

## 0.4 package/publication policy

The distributed package must be self-contained and contain no repository-relative production dependency.

```text
Android       android/build.gradle -> ../cargokit -> ../rust
iOS/macOS     podspec -> ../cargokit/build_pod.sh -> ../rust
Linux/Windows CMakeLists.txt -> ../cargokit/cmake/cargokit.cmake -> ../rust
```

`make package-readiness` runs docs generation and `dart pub publish --dry-run --ignore-warnings`. A green dry-run alone is not native build evidence.

## PH-04 published-payload consumer policy

`tool/validate_published_consumer.dart` stages a consumer-visible package tree according to the current explicit `.pubignore` rules plus hidden-file exclusion, then verifies required native inputs, rejects repository-only leakage/path-source dependencies, creates a fresh Flutter application, points it only at the staged package, imports the public API, and builds the selected platform.

Supported gates:

```text
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

`Platform Builds` runs the staged-consumer flow on all five targets. The validator fails closed if `.pubignore` introduces wildcard/negation syntax it does not model exactly. `dart pub publish --dry-run` remains authoritative for pub validation/file listing; PH-04 is complementary build evidence, not a replacement.

## 0.4 local-database comparison policy

Comparison-only dependencies stay under `benchmark/` and do not affect root SDK or production dependencies.

Engines:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

Correctness CRUD/delete/reopen equivalence is a hard gate. Timing scenarios (`sequential_put`, `batch_put`, `point_get`, `contains`, `delete_all`, `reopen_read`) are diagnostic only. Hosted-runner timings are not stable marketing benchmarks.

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
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

## 0.4 Production Hardening sequence

### PH-01 — Cross-commit native-size regression policy — complete (PR #27)

### PH-02 — Package-quality / publication hardening — complete (PR #28)

### PH-03 — Broader Flutter local-database comparison — complete (PR #29)

Acceptance completed: four engines, benchmark-only comparison dependencies, correctness hard gate, timing-only diagnostics, machine-readable CI evidence, no speculative threshold optimization.

### PH-04 — Published-payload consumer validation — active

Acceptance:

- staged payload follows current publication exclusions and prunes ignored directories before traversal;
- required Dart/Rust/Cargokit/platform files are present;
- repository-only files and root path-source dependencies are absent;
- a fresh consumer imports the public API from staged `dxtr_box` only;
- Android/iOS/macOS/Linux/Windows consumer builds pass;
- `.pubignore` and validator changes trigger Platform Builds;
- README, handoff, walkthrough, `PACKAGE_RELEASE_04.md`, and `PUBLISHED_PAYLOAD_CONSUMER_04.md` agree.

## Deferred beyond current 0.4 slice

- encrypted persisted-index design;
- order-preserving scalar encoding / scalar-level redb range seeks;
- index-backed ORDER BY;
- Dart 3.13 recorded-use/native tree shaking;
- LazyBox migration and direct `.hive` parsing;
- file-level crash-atomic Hive migration staging/promotion and stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB and remaining 1.0 Hive functional-parity gaps.

Do not reopen closed query/index/migration work or optimize benchmark timings without demonstrated product-relevant evidence and matching regression/equivalence coverage.

## Later roadmap

### 0.9.x

Refresh Hive Functional Parity Audit against the then-current Hive CE release and close every practical `Gap`.

### 1.0.0

- no practical parity gaps;
- stable storage/API contract;
- Web/IndexedDB strategy complete;
- pub.dev release readiness.
