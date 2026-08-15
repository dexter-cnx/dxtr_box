# dxtr_box Testing Strategy

The test suite is layered so failures identify whether the problem is in Dart behavior, serialization, native storage, cross-platform compilation, process-boundary durability, or benchmark harness execution.

## Local commands

Preferred entry points:

```bash
make preflight
make native-test
make process-crash
make benchmark-smoke
```

Run the Dart/Flutter checks directly:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test example
flutter analyze
flutter test --reporter expanded
```

Run the Rust checks directly:

```bash
cargo fmt --manifest-path rust/Cargo.toml -- --check
cargo clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings
cargo test --manifest-path rust/Cargo.toml --all-targets
cargo test --manifest-path rust/Cargo.toml --all-targets --features encryption
```

## Dart codec tests

File: `test/codec_test.dart`

Coverage:

- null
- bool
- int
- double
- String
- List
- nested `Map<String, dynamic>`
- `Uint8List`
- `DateTime`
- rejection of non-string map keys

These tests verify the application-facing dynamic value contract independently from Rust.

## Dart Box tests

File: `test/box_test.dart`

These tests use an in-memory `NativeDxtrApi` fake. They exercise Dart semantics without loading an FFI library.

Coverage includes:

- metadata hydration during `DxtrBox.open()`
- key metadata updates after put/delete/deleteAll/clear
- put/get/containsKey
- missing-key default values
- putAll
- deleteAll de-duplication and metadata behavior
- compact facade delegation
- where predicates over decoded values
- native-backed watch filtering/fan-out semantics through the fake seam
- clear event forwarding
- idempotent close
- closed-box guards
- unsafe box-name rejection
- deleteBox/boxExists delegation

The fake is a test seam only. It does not replace native integration tests.

## Native Dart -> FRB integration tests

File: `test/native_integration_test.dart`

Run with:

```bash
make native-test
```

Coverage includes real Dart -> FRB -> Rust -> redb behavior for:

- persistence across close/reopen
- dynamic MessagePack values
- same-box multi-handle access
- cross-handle native watch delivery
- encrypted close/reopen
- wrong/missing encryption key rejection
- deleteAll and compaction native paths

These tests require the native release library and are gated with `DXTR_BOX_NATIVE_TEST=1`.

## Rust engine tests

Primary unit coverage lives in `rust/src/db.rs` and related Rust modules.

Coverage includes:

- CRUD round trip
- contains-key behavior
- write transactions
- persistence across close/reopen
- putAll pre-validation before write
- deleteAll transaction/results
- compaction lifecycle and exclusivity
- invalid box-name rejection
- delete-box file/cache behavior
- encryption metadata and unique salt behavior
- encrypted at-rest payloads
- wrong/missing-key rejection
- tamper rejection
- plaintext/encrypted mode mismatch

### Global-state test isolation

The engine has process-global base-path, database-cache, watcher, and mutation-lock state. Same-process tests must avoid racing global reinitialization. Test-only synchronization is allowed where needed as long as production synchronization semantics are not weakened.

## Process-kill durability test

File: `rust/tests/process_crash.rs`

Run with:

```bash
make process-crash
```

This test proves a stronger boundary than ordinary `close()` / reopen coverage:

1. The parent creates a temporary database directory.
2. A child instance of the Rust test executable initializes the directory.
3. The child opens plaintext and encrypted boxes.
4. The child completes several committed transactions.
5. Only after the final committed write returns, the child prints `DXTR_BOX_COMMITTED` and flushes stdout.
6. The parent receives that marker and kills the child process while both boxes remain open.
7. A fresh process context reopens the same files and verifies all previously committed plaintext and encrypted values.

The test deliberately makes **no guarantee for writes that had not returned successfully before termination**. It validates recovery of acknowledged commits, which is the contract dxtr_box should claim at this stage.

## Benchmark smoke harness

File: `test/benchmark_smoke_test.dart`

Comparison dependency: `hive_ce`.

Run the CI-sized smoke workload:

```bash
make benchmark-smoke
```

Run a larger local workload:

```bash
make benchmark-full
```

Override operation counts when needed:

```bash
make benchmark-smoke BENCHMARK_OPS=500
make benchmark-full BENCHMARK_FULL_OPS=10000
```

Current scenarios use the same logical payload shape and operation count for both engines:

- sequential put
- batch put / putAll
- point get
- contains
- deleteAll
- reopen + read

Methodology:

- warm-up runs are excluded from reported samples
- five measured samples are collected per engine/scenario
- output records median, minimum, maximum, and raw samples in microseconds
- machine-readable lines begin with `DXTR_BOX_BENCHMARK`
- setup outside the named scenario is excluded from timing where practical
- `reopen_read` intentionally includes reopen because reopen cost is part of that scenario
- timing results are informational only

The smoke test asserts that both benchmark paths execute and emit results. It does **not** assert that dxtr_box is faster than Hive CE, and CI does not enforce absolute latency thresholds on shared runners.

Future benchmark work should add file-size reporting, more payload sizes, delete-vs-deleteAll separation, and retained result artifacts before making performance claims.

## CI

Workflow: `.github/workflows/ci.yml`

### Flutter job — Ubuntu

- checkout
- install stable Flutter
- `flutter pub get`
- formatting check
- `flutter analyze`
- `flutter test`

Benchmark smoke is skipped in the general Flutter test job unless explicitly enabled.

### Native Linux job

- build the Rust release library
- run Dart -> FRB -> Rust native integration tests
- run the `hive_ce` benchmark smoke harness with a deliberately small operation count

The benchmark step is an execution/regression check, not a performance threshold gate.

### Rust host matrix

Runs on:

- Ubuntu
- macOS
- Windows

Each host runs:

- rustfmt check
- clippy with warnings denied
- default-feature tests
- encryption-feature tests

`cargo test --all-targets` includes the process-kill integration test, giving crash/reopen coverage on every supported Rust CI host where the test process can be killed normally.

## Platform build validation

The example app is compiled on Android, iOS without code signing, macOS, Linux, and Windows through the existing build matrix/workflows. Native build ownership remains in `rust_builder/`.

## Still not a quality gate

The following remain future hardening work:

- benchmark absolute performance thresholds
- long-duration benchmark trend regression policy
- release binary-size regression measurement
- Dart 3.13 native symbol tree-shaking verification
- explicit plaintext -> encrypted migration interruption/recovery tests

Performance CI should remain trend-oriented rather than a brittle absolute timing gate on shared GitHub runners.
