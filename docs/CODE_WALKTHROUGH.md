# dxtr_box Code Walkthrough

This walkthrough describes the current **0.10** architecture: one authoritative Rust/redb engine with a Flutter/Dart frontend through flutter_rust_bridge and a first-class native Rust frontend.

## 1. Package and durable boundary

```text
dxtr_box/
  lib/                 Dart API + generated FRB bindings
  rust/                Rust crate/library: rust_lib_dxtr_box
  benchmark/           deterministic diagnostics and workload runners
  tool/                reproducible CI/local evidence scripts
  android/ ios/ macos/ linux/ windows/
  example/             Flutter consumer
```

Stable contract:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
format_version = dxtr_box/1
package version = 0.10.0-dev.1
```

Each box maps to `{base_path}/{box_name}.dxtr`. There is no Dart-only or Rust-only storage format.

## 2. Dependency direction

```text
Dart API -> FRB adapter ----┐
                            ├-> shared authoritative Rust core -> redb
Rust API -------------------┘
```

The native Rust frontend never calls Dart or FRB. GPUI is not a dependency of the core package.

Primary Rust boundaries:

```text
rust/src/api.rs       FRB-facing bridge adapter
rust/src/native.rs    native Rust facade
rust/src/core.rs      shared authoritative operations
rust/src/db.rs        redb/storage mechanics
rust/src/query.rs     canonical query representation/evaluation
rust/src/index*.rs    persisted index implementation
rust/src/error.rs     structured Rust errors
```

## 3. Mutation path

Dart:

```text
Box.put / putAll / delete / deleteAll / clear
  -> BoxCodec
  -> NativeBoxApi
  -> generated FRB
  -> shared Rust core
  -> optional encryption
  -> one redb write transaction
  -> primary + derived index changes
  -> commit
  -> watch event after commit
```

Rust-native:

```text
DxtrBox / BoxHandle mutation
  -> shared Rust core
  -> same redb/encryption/index transaction path
```

Primary records remain authoritative and indexes remain derived state.

## 4. Reads and queries

Point and batch reads converge on shared core operations and fresh redb read transactions. `getAll/get_all` preserves hit order, omits misses, and preserves duplicate input hits.

There is no Dart whole-box cache or long-lived stale read snapshot.

Query authoring converges before execution:

```text
Dart BoxQuery/BoxQueryBuilder ----┐
                                  ├-> canonical QuerySpec -> planner -> redb
Rust QueryBuilder ----------------┘
```

Persisted indexes narrow candidates only; authoritative primary records are still read and predicates rechecked. Encrypted equality narrowing uses keyed tokens under `full`; encrypted ordered/range predicates remain scan-backed.

## 5. Native profiles

Exactly three profiles remain:

```text
minimal
encryption
full
```

`full` is default. Do not add a fourth profile to support benchmark or frontend-specific behavior.

## 6. Cross-frontend conformance

0.8 established bidirectional same-file compatibility. 0.9 added reusable conformance tests for CRUD, overwrite, batch ordering/duplicates/misses, enumeration, deletion, clear, and index lifecycle behavior.

Both frontends therefore share one durable contract before 0.10 workload timing is accepted.

## 7. 0.10 deterministic workload fixtures

`benchmark/lib/real_world_workloads.dart` defines three deterministic application-shaped datasets:

```text
settings_session
catalog_workspace
activity_event
```

Fixture rules:

- fixed timestamps;
- stable keys/order;
- deterministic payload generation;
- stable nested metadata;
- no random or wall-clock drift.

The Rust-native benchmark fixture generation in `rust/src/real_world_bench.rs` mirrors the Dart fixture shapes and deterministic values so the frontends are not timed against materially different records.

## 8. Dart/FRB workload runner

`benchmark/lib/real_world_dxtr_runner.dart` executes the three scenarios through the public Dart API and generated FRB boundary.

Each emitted result includes:

```text
frontend = dart_frb
scenario
records
samples
operations_per_sample
operation_unit = logical_records
elapsed_us
median_us
min_us
max_us
dart_build_mode
native_build_mode
```

Correctness checks execute before accepting the evidence.

## 9. Rust-native workload runner

`rust/src/real_world_bench.rs` runs equivalent logical scenarios through the public Rust-native facade and emits `DXTR_BOX_REAL_WORLD_RUST` JSONL records.

It validates batch ordering/identity, catalog deletion, activity retention, and settings overwrite behavior while keeping untimed cleanup outside the timed sample loops.

## 10. Reproducible 0.10 evidence

Run:

```bash
bash tool/real_world_workloads.sh
```

The script:

1. builds the release native library;
2. runs the ignored Rust-native real-world benchmark;
3. extracts exactly three Rust JSONL records;
4. runs the Dart/FRB benchmark with the same record/sample counts and release native library;
5. extracts exactly three Dart JSONL records;
6. records Rust/Cargo/Flutter/Dart toolchain metadata.

Outputs:

```text
build/real-world/rust-native.jsonl
build/real-world/dart-frb.jsonl
build/real-world/rust-native.log
build/real-world/dart-frb.log
build/real-world/toolchain.txt
```

`.github/workflows/real_world_workloads.yml` runs the same script on Ubuntu and uploads the evidence directory as a GitHub Actions artifact.

## 11. Interpretation rule

0.10 evidence is diagnostic, not a leaderboard. Cross-frontend deltas include Dart runtime, serialization, generated FRB, and FFI boundary costs. They must not be described as pure redb/storage-engine speedups.

Compare only runs with matching fixture sizes, sample counts, build modes, and toolchain context.

## 12. Merge quality bar

Full validation continues to cover:

```text
format + analyze
Dart tests
Flutter 3.22 / Dart 3.4 minimum SDK
Rust minimal/encryption/full tests
native integration
migration/query/index/crash-reopen regression
FRB generated bindings
native-size policy
package/pub dry-run
benchmark correctness/smoke
Android/Linux/Windows/macOS/iOS staged consumers
```

0.10 adds evidence infrastructure without weakening these gates.

## 13. 0.10 boundary and next step

0.10 closes without adding a runtime cache, startup fast path, storage metadata, query-engine rewrite, encryption redesign, ORM, sync layer, GPUI dependency, Tokio commitment, or fourth native profile.

See:

- `docs/REAL_WORLD_WORKLOADS_010.md`
- `docs/REAL_WORLD_CROSS_FRONTEND_010.md`
- `docs/RELEASE_AUDIT_010.md`
- `docs/PROJECT_HANDOFF.md`

After 0.10 closure, work returns to 1.0 stabilization starting with PR #57 contract-freeze audit and stronger release guards.
