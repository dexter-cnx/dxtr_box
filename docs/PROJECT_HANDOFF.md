# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 goal is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot

Closed milestones:

- 0.3 query/index/migration complete.
- 0.4 Production Hardening PH-01 through PH-05 complete.
- PR #27 native-size regression policy.
- PR #28 package/publication hardening.
- PR #29 four-engine correctness + diagnostic comparison.
- PR #30 staged published-payload five-platform consumer validation.
- PR #31 public API + durable-storage contract guard.

Current milestone:

```text
0.5 — Performance / Read-path Optimization
PR 1 — read-path benchmark decomposition: corrected evidence baseline complete
PR 2 — single-key read optimization: next, boundary-first investigation
```

Normative performance document:

- `docs/PERFORMANCE_READ_PATH_05.md`

## Stable package/runtime contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Dart:                   >= 3.4.0 < 4.0.0
Flutter:                >= 3.22.0
flutter_rust_bridge:    2.8.0 exactly
redb:                    2.1.0
durable format:         meta[format_version] = dxtr_box/1
```

Exactly three public native capability profiles remain:

```text
minimal
encryption
full
```

`full` is default. Do not add a fourth profile for performance work.

Dart 3.13 recorded-use/native tree shaking remains deferred outside current 0.5 work unless requested separately.

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
- 0.5 decomposed read-path benchmark with machine-readable Rust + Dart evidence.

## Hard correctness invariants

### Storage / mutation

Primary `data` is authoritative; persisted indexes are derived state.

```text
put / putAll / delete / deleteAll / clear
  -> compute primary + index changes
  -> one redb write transaction
  -> one commit
  -> watch events only after commit
```

### Point reads

```text
Box.get
  -> NativeDxtrApi.get
  -> FRB
  -> Rust db::get
  -> redb read transaction + lookup
  -> optional decrypt/authenticate
  -> native MessagePack validation
  -> payload return
  -> DxtrCodec.decode
```

`Box.get` and `Box.containsKey` remain authoritative native reads. Do not substitute Dart key metadata or a Dart whole-box cache because cross-handle/cross-process freshness would be weakened.

Encrypted reads must retain full AEAD authentication.

### Query execution

```text
Box.query(BoxQuery)
  -> serialize AST
  -> one FRB call
  -> one redb ReadTransaction snapshot
  -> optional persisted-index narrowing
  -> authoritative primary reads from same snapshot
  -> decrypt if required
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

Indexes narrow candidates only. They do not replace predicate re-evaluation and do not currently satisfy ORDER BY.

### Encryption/index safety

Encrypted boxes can use scan queries but cannot create persisted plaintext-derived secondary indexes. Plaintext-to-encrypted migration is rejected while persisted index definitions exist. Reduced native profiles reject boxes containing persisted indexes because they cannot safely maintain derived state.

## 0.5 Phase A — corrected evidence baseline

PR #33 introduces measurement-only decomposition. No production read behavior was optimized in PR 1.

The first artifact-producing run (#7) exposed an important review issue: the Rust medium payload used a `Vec<u8>` body, which `rmp-serde` encoded as a 4,096-element sequence, while the public Dart workload used `DxtrCodec`'s tagged map with a 4,096-character string. That inflated native MessagePack validation and invalidated the original conclusion that validation dominated the medium read.

The Rust harness was corrected to encode the same logical public wire shape. The superseding baseline is:

```text
Read-path Benchmark #11
run id:      31949461503
artifact:    read-path-benchmark-linux-x64
artifact id: 9264234449
head:        09c407139b824c3cbb6ce12f3bd8dacf84d03285
```

Runner/toolchain:

```text
Ubuntu hosted runner / Linux x86_64 / kernel 6.17.0-1022-azure
Intel Xeon Platinum 8370C @ 2.80GHz / 4 logical CPUs
Flutter 3.47.0
Dart 3.13.0
rustc 1.97.1
cargo 1.97.1
```

Artifact contents are complete and include:

```text
rust-read-path.jsonl
dart-read-path.jsonl
flutter-version.txt
rust-version.txt
cargo-version.txt
runner.txt
cpu.txt
```

The Makefile fails if either JSONL file is missing. Rust output uses an absolute repository-root path so Cargo test working-directory behavior cannot silently place evidence under `rust/build/...`.

### Measured Rust facts from corrected run #11

Representative medians:

```text
small payload
  transaction create             0.199 us
  transaction + table open       0.492 us
  borrowed lookup hit            0.100 us
  lookup + copy hit              0.107 us
  MessagePack validation         0.084 us
  full plaintext db_get hit      0.742 us
  decrypt/authenticate           1.700 us
  full encrypted db_get hit      2.454 us

medium payload (~4 KiB string body in public wire shape)
  transaction create             0.200 us
  transaction + table open       0.567 us
  borrowed lookup hit            0.116 us
  lookup + copy hit              0.191 us
  MessagePack validation         0.211 us
  full plaintext db_get hit      1.055 us
  decrypt/authenticate           4.952 us
  full encrypted db_get hit      6.056 us
```

Medium in-process misses and `containsKey` remain around ~0.65 us.

### Measured Dart/public-path facts from corrected run #11

Representative medians:

```text
Dart DxtrCodec.decode
  small                         10.368 us
  medium                         5.972 us

native adapter plaintext get hit
  small                        132.822 us
  medium                        90.470 us

public Box.get plaintext hit
  small                        102.628 us
  medium                       102.118 us

native adapter contains hit
  small                         78.396 us
  medium                        74.310 us

public Box.containsKey hit
  small                         76.318 us
  medium                        74.672 us
```

The shared-runner Dart measurements are non-monotonic across adjacent layers in some cases, so they are diagnostic end-to-end baselines, not additive component timers.

### Evidence-based conclusion

**Measured fact:** corrected medium plaintext `db_get` is ~1.06 us in-process. Native MessagePack validation is only ~0.21 us, lookup+copy ~0.19 us, and transaction+table open ~0.57 us. The earlier ~17.37 us validation result is superseded and must not guide production work.

**Inference:** the large structural gap between in-process Rust (`db_get` ~1.06 us, `containsKey` ~0.65 us) and Dart native-adapter/public paths (~74–102 us) makes the cross-runtime/generated-FRB/Dart-async region the highest-priority end-to-end investigation. This is not a direct FRB-only measurement and must not be quoted as an exact FRB percentage.

**Implemented optimization:** none in PR 1 by design.

**Priority implication:** PR 2 should first isolate the bridge/async/conversion region with a controlled diagnostic, then choose a production single-key optimization. Native validation/copy cleanup is secondary unless controlled end-to-end evidence shows otherwise. Long-lived read sessions are not the first target.

## PR 2 — next: single-key read optimization

PR 2 must be evidence-driven.

Investigation order:

1. Preserve the corrected public-wire benchmark payload shape.
2. Add a controlled diagnostic for generated FRB call overhead versus Dart async adapter/conversion work without leaving benchmark-only production API surface behind.
3. Inspect generated FRB call mode, request/response conversion, async scheduling, and payload allocation/copy behavior.
4. Select a production optimization only after the boundary diagnostic identifies an actionable source of cost.
5. Keep native transaction/validation/copy cleanup as secondary work unless end-to-end evidence elevates it.
6. Preserve full encryption authentication.
7. Preserve authoritative native reads and cross-process visibility.
8. Do not introduce stale long-lived snapshots as a shortcut.
9. Record before/after evidence using the same methodology/environment where practical.

## Planned 0.5 sequence

```text
PR 1 — read-path benchmark decomposition                         corrected evidence baseline
PR 2 — single-key read optimization                              next
PR 3 — batch/multi-key read path
PR 4 — read-session investigation / explicit session only if safe
PR 5 — comparison matrix + 0.5 closure audit
```

### PR 3 — batch/multi-key reads

High priority after single-key work. Preferred shape:

```text
N keys
  -> one FRB call
  -> one redb read transaction/snapshot
  -> N lookups
  -> one response
```

Define missing-key and duplicate-key semantics explicitly. Support encrypted boxes. Add Dart/Rust/native integration tests and 10/100/1,000-key benchmarks.

### PR 4 — read-session investigation

Evaluate redb transaction lifetime, writer interaction, stale snapshots, resource retention, Flutter lifecycle, multi-handle behavior, and cross-process expectations.

Do not silently change ordinary `get` to use a long-lived stale snapshot. If reusable sessions are justified, prefer explicit session semantics. Document the decision even if the answer is “do not implement.”

### PR 5 — expanded comparison + closure

Compare at minimum:

```text
dxtr_box
Hive CE
Sembast
SQLite / sqflite_common_ffi
```

Scenarios should include sequential put, batch put, point get, contains, batch/multi-key get, reopen+read, and mixed read-heavy workloads at representative dataset/payload sizes.

Timing stays diagnostic. Correctness remains the hard gate.

## Hive CE migration contract

Core `dxtr_box` has no runtime Hive CE dependency. Preserve:

- source remains open/unmodified;
- String keys preserved;
- int keys default to `@hive-int:<decimal>`;
- custom conversion explicit;
- collision/unsupported-value preflight;
- `DxtrCodec` preflight before destination creation;
- exclusive migration reservation;
- migration/open exclusion;
- failure cleanup;
- one destination `putAll` / one native write transaction.

## 0.4 policies that remain active

### Native-size

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
```

Measure minimal/encryption/full independently. Intentional growth must be reviewed with measured deltas.

### Package/publication

Published package remains self-contained. No repository-relative production dependency may leak outside the package root.

### Published-payload consumers

Fresh staged package payload must build Android/iOS/macOS/Linux/Windows consumers.

### Public API + storage contract

```text
public entrypoint: package:dxtr_box/dxtr_box.dart
storage key:       format_version
storage format:    dxtr_box/1
```

Deliberate public API/storage changes require matching compatibility tests/docs/migration design.

## Developer workflow

Preferred root targets:

```text
make preflight
make package-readiness
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
3. `get` / `containsKey` improve where the identified bottleneck permits it.
4. Efficient multi-key support exists or an evidence-based rejection is documented.
5. No Dart whole-box cache.
6. No durability/cross-process regression.
7. No encryption/authentication weakening.
8. No silent storage-format change; `dxtr_box/1` remains readable.
9. Exactly three native profiles remain.
10. Dart >=3.4 / Flutter >=3.22 remain supported.
11. FRB bindings remain reproducible and pinned to 2.8.0.
12. Query/index/migration functionality stays green.
13. Native-size gate stays green.
14. Android/iOS/macOS/Linux/Windows staged consumer builds stay green.

## Working style

Use small focused branches/PRs. After each merged PR:

- update `docs/PROJECT_HANDOFF.md`;
- update `docs/CODE_WALKTHROUGH.md`;
- update README only when public behavior changes;
- remove obsolete merged branches;
- keep temporary CI/debug tooling out of final branches;
- verify normal CI and Platform Builds.

## Deferred beyond current slice

- Dart 3.13 recorded-use/native tree shaking;
- encrypted persisted-index design;
- order-preserving scalar encoding / scalar-level redb range seeks;
- index-backed ORDER BY;
- LazyBox migration / direct `.hive` parsing;
- crash-atomic Hive migration staging/promotion and stale-reservation recovery;
- application bundle/APK/IPA size budgets;
- Web/IndexedDB and remaining 1.0 Hive functional-parity gaps.

Do not trade correctness, durability, encryption, cross-process visibility, or compatibility for benchmark numbers.
