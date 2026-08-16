# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 claim is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot — 0.5 Performance / Read-path Optimization started

Closed milestones:

- 0.3 query/index/migration is complete.
- 0.4 Production Hardening PH-01 through PH-05 is complete.
- PR #27 PH-01 controlled cross-commit native-size regression policy.
- PR #28 PH-02 self-contained package/publication hardening.
- PR #29 PH-03 broader Flutter local-database correctness + diagnostic comparison.
- PR #30 PH-04 published-payload consumer validation on Android/iOS/macOS/Linux/Windows.
- PR #31 PH-05 public API + durable storage contract guard.

Current milestone:

```text
0.5 — Performance / Read-path Optimization
PR 1 — read-path benchmark decomposition
```

PR 1 is intentionally measurement-only. Do not make speculative production read optimizations until the decomposition evidence identifies the dominant costs.

Normative 0.5 performance document:

- `docs/PERFORMANCE_READ_PATH_05.md`

Normative 0.4 docs remain:

- `docs/PACKAGE_RELEASE_04.md`
- `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md`
- `docs/PUBLIC_API_STORAGE_CONTRACT_04.md`
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

FRB remains intentionally pinned exactly because checked-in generated bindings, Dart runtime, Rust runtime, codegen, and macros must remain version-aligned.

Durable storage identity remains:

```text
meta[format_version] = dxtr_box/1
```

Exactly three public native profiles remain:

```text
minimal     CRUD + lifecycle + native watch
encryption  minimal + encrypted create/open/read/write
full        encryption + maintenance + query/index implementation
```

`full` is default. Do not add a fourth public profile for performance tuning.

Dart 3.13 recorded-use/native tree shaking is explicitly deferred outside 0.5 unless requested separately.

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
- Fresh staged-payload consumer builds on all five native targets.
- Public-export and durable-format compatibility guards under the normal Flutter test suite.

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

### Point reads

```text
Box.get
  -> NativeDxtrApi.get
  -> FRB
  -> Rust
  -> redb read transaction / lookup
  -> optional decrypt/authenticate
  -> native MessagePack validation
  -> payload allocation/copy
  -> FRB return
  -> DxtrCodec.decode
```

`Box.get` remains authoritative against native storage.

`Box.containsKey` remains authoritative against native storage. Dart metadata/key snapshots may be useful UI conveniences but must not replace authoritative reads because cross-handle/cross-process freshness would be weakened.

No Dart whole-box read cache is permitted as a benchmark shortcut in 0.5.

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

Encrypted point reads must retain full AEAD authentication throughout 0.5. Do not optimize by skipping authentication or changing the durable ciphertext format without a separately reviewed compatibility/migration design.

## 0.5 Phase A — Decompose point-read cost

### Previous measured fact

The 0.3 shared-runner diagnosis observed approximately:

```text
native plaintext get hit       225.726 us/op
Dart MessagePack decode only     6.018 us/op
native containsKey hit         193.830 us/op
Dart metadata membership         6.532 us/op
```

See `docs/POINT_READ_DIAGNOSIS_03.md`.

These timings are diagnostic only. They establish that the composite native region dominated that run; they do not establish whether redb transaction setup, redb lookup, native validation, crypto, copying, or FRB was dominant inside that region.

### PR 1 implementation

PR 1 adds a purpose-built decomposition without changing production Box behavior:

```text
rust/src/read_path_bench.rs
  -> read transaction setup
  -> read transaction + table open
  -> stable-snapshot raw redb lookup hit/miss
  -> raw lookup + value copy
  -> MessagePack validation
  -> native Vec copy baseline
  -> decrypt/authenticate
  -> full in-process db::get
  -> full in-process db::contains_key

test/read_path_benchmark_test.dart
  -> Dart DxtrCodec.decode
  -> FrbNativeDxtrApi.get
  -> public Box.get
  -> FrbNativeDxtrApi.containsKey
  -> public Box.containsKey
```

Both small and medium payloads are measured. Hit/miss and plaintext/encrypted cases are included where relevant. Repeated iterations, warmup, multiple samples, and median ns/op output reduce timer noise.

Machine-readable evidence:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

Run locally:

```text
make benchmark-read-path
```

The dedicated `Read-path Benchmark` GitHub Actions workflow archives both JSONL files plus Flutter/Rust/Cargo/runner/CPU metadata.

### FRB measurement rule

PR 1 does not add a benchmark-only FRB echo endpoint to the shipped library.

Therefore any FRB/native-boundary estimate is an **inference** from the gap between the Dart native-adapter measurements and the corresponding Rust in-process database measurements from the same CI job. That gap also contains Dart async adapter work and cross-harness timer/runtime effects; it must not be described as an exact FRB percentage.

### Implemented optimization

None yet. This is intentional until PR 1 evidence exists.

## Planned 0.5 sequence

```text
PR 1 — read-path benchmark decomposition
PR 2 — single-key read optimization
PR 3 — batch/multi-key read path
PR 4 — read-session investigation / implementation only if justified
PR 5 — full comparison matrix + 0.5 closure audit
```

### PR 2 — single-key read optimization

Use PR 1 evidence only. Potential areas include transaction setup, avoidable allocations/copies, duplicate native validation/conversion, unnecessary work on misses, and FRB conversion overhead.

Requirements:

- `Box.get` remains authoritative native storage.
- `Box.containsKey` remains authoritative native storage.
- no Dart metadata replacement;
- no encryption/authentication weakening;
- cross-process visibility contract preserved;
- before/after evidence recorded using the same methodology/environment where possible.

### PR 3 — multi-key / batch reads

High priority. Investigate a product-grade API such as `getAll(Iterable<String> keys)` or an equivalent design.

Target shape:

```text
N keys
  -> one FRB call
  -> one redb read transaction/snapshot
  -> N lookups
  -> one response
```

Define deterministic missing-key and duplicate-key behavior explicitly. Support encrypted boxes. Preserve codec/type behavior. Add Dart, Rust, and native integration tests plus 10 / 100 / 1,000-key benchmarks.

Do not add an API only for benchmark convenience.

### PR 4 — read-session investigation

Evaluate redb transaction lifetime, writer interaction, stale snapshots, resource retention, Flutter lifecycle, multi-handle behavior, and cross-process expectations.

Do not silently change ordinary `get` to read from a long-lived stale snapshot. If a reusable session is justified, prefer explicit session semantics. Document the decision even if the conclusion is "do not implement".

### PR 5 — comparison matrix + closure

Use the existing 0.4 comparison framework and compare at minimum:

```text
dxtr_box
Hive CE
Sembast
SQLite / sqflite_common_ffi
```

Scenarios:

```text
sequential put
batch put
point get
contains
batch/multi-key get
reopen + read
mixed read-heavy workload
```

Representative dataset sizes should include 100 / 1,000 / 10,000 with multiple payload sizes where useful.

Shared CI timing remains diagnostic. Correctness remains the hard gate; CI must not fail because another engine is faster.

## Performance evidence policy

Every production performance change records:

```text
before
after
delta
benchmark methodology
hardware/runner metadata where available
correctness validation
```

Prefer controlled before/after evidence on the same runner/toolchain/methodology. Do not make user-facing performance claims from speculative inference or unrelated shared-runner runs.

Success is not defined as beating Hive CE in every point-read benchmark. The goal is to eliminate avoidable Dxtr_Box overhead, improve read-heavy real workloads, make batching efficient, and preserve durability/native-storage advantages.

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

## 0.4 hardening policies that remain active

### Native-size policy

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
fail when head_bytes - base_bytes > allowed_growth
```

Base/head are detached committed snapshots built under one OS/arch/rustc/cargo environment with isolated target dirs. Evidence is `native-size-regression.tsv`. Intentional growth must be reviewed with measured deltas rather than hidden by bypassing the gate.

### Package/publication policy

The distributed package must be self-contained and contain no repository-relative production dependency.

```text
Android       android/build.gradle -> ../cargokit -> ../rust
iOS/macOS     podspec -> ../cargokit/build_pod.sh -> ../rust
Linux/Windows CMakeLists.txt -> ../cargokit/cmake/cargokit.cmake -> ../rust
```

`make package-readiness` runs docs generation and `dart pub publish --dry-run --ignore-warnings`.

### Published-payload consumer policy

`tool/validate_published_consumer.dart` stages the consumer-visible package tree and validates fresh Android/iOS/macOS/Linux/Windows consumer builds from that staged payload. The validator fails closed if `.pubignore` uses unsupported semantics.

### Public API + storage contract policy

The current public entrypoint export set and durable storage identity are reviewed compatibility boundaries.

```text
package:dxtr_box/dxtr_box.dart
storage meta key: format_version
storage format:   dxtr_box/1
```

A deliberate 0.x public API change must update compatibility tests/docs in the same PR. A storage-format change additionally requires backward-read or migration behavior and compatibility evidence.

## Developer workflow

Preferred root targets:

```text
make preflight
make package-readiness
dart run tool/verify_public_storage_contract.dart
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
make benchmark-read-path
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

## 0.5 acceptance criteria

Do not close 0.5 merely because benchmarks exist.

Require:

1. Bottlenecks decomposed with evidence.
2. At least one production read-path optimization implemented and measured.
3. `get` and `containsKey` measurably improve where the identified bottleneck permits it.
4. Efficient multi-key support exists or an evidence-based reason not to implement it is documented.
5. No Dart whole-box cache.
6. No durability regression.
7. No cross-process correctness regression.
8. No encryption/authentication weakening.
9. No silent storage-format change.
10. `dxtr_box/1` remains readable.
11. Exactly three native profiles remain.
12. Dart >=3.4 / Flutter >=3.22 remain supported.
13. FRB generated bindings remain checked/reproducible.
14. Existing query/index/migration functionality remains green.
15. Native-size regression gate remains green.
16. Android/iOS/macOS/Linux/Windows consumer builds remain green.

## Working style

Use small focused branches/PRs. After each merged PR:

- update `docs/PROJECT_HANDOFF.md`;
- update `docs/CODE_WALKTHROUGH.md`;
- update README only when public behavior changes;
- remove obsolete branches;
- keep temporary CI/debug tooling out of the final branch;
- verify normal CI and Platform Builds.

## Deferred beyond current 0.5 slice

- Dart 3.13 recorded-use/native tree shaking;
- encrypted persisted-index design;
- order-preserving scalar encoding / scalar-level redb range seeks;
- index-backed ORDER BY;
- LazyBox migration and direct `.hive` parsing;
- file-level crash-atomic Hive migration staging/promotion and stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB and remaining 1.0 Hive functional-parity gaps.

Do not trade correctness, durability, encryption, cross-process visibility, or compatibility for benchmark numbers.
