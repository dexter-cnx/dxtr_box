# dxtr_box Testing Strategy

The test suite is layered so failures identify whether the problem is in Dart behavior, serialization, native storage, cross-platform compilation, minimum-SDK compatibility, process-boundary durability, generated bridge drift, or benchmark harness execution.

## Local commands

Preferred entry points:

```bash
make preflight
make native-test
make process-crash
make benchmark-smoke
make native-size-stability
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
cargo test --manifest-path rust/Cargo.toml --all-targets --no-default-features
cargo test --manifest-path rust/Cargo.toml --all-targets --no-default-features --features encryption
cargo test --manifest-path rust/Cargo.toml --all-targets
```

## Minimum SDK compatibility

Declared package floor:

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

Flutter 3.22.0 ships Dart 3.4.0. CI therefore tests that exact pair rather than merely lowering the Dart constraint while continuing to run a newer Flutter SDK.

The minimum-SDK lane must run at least:

- `flutter pub get`
- `flutter analyze`
- `flutter test`

This lane exists to catch accidental use of newer language features, SDK APIs, or dependency upgrades that silently raise the real compatibility floor.

Dev dependencies that are required to validate the root package are part of this check. `flutter_lints 5.x`, for example, requires Flutter 3.24 / Dart 3.5, so the root package uses a compatible 4.x line while Flutter 3.22 / Dart 3.4 remains the declared minimum.

Benchmark-only dependencies are intentionally not part of the root package compatibility surface. The current `hive_ce` benchmark lives in the separate `benchmark/` package because Hive CE 2.19.x requires a newer `meta` range than the Flutter 3.22 SDK pins through its SDK test packages. Keeping the benchmark isolated lets dxtr_box prove its lower SDK floor without downgrading the comparison target to an obsolete Hive CE release.

A future minimum-SDK increase should be intentional, documented in the handoff/changelog, and accompanied by a CI update. Dart 3.13 native tree shaking is explicitly not a reason to raise the floor today; see `docs/FUTURE_NATIVE_TREE_SHAKING.md`.

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

The primary `NativeDxtrApi` seam remains usable by test/alternate engines that do not implement encryption migration. Migration is exposed as the optional `NativeEncryptionMigrationApi` capability so adding the maintenance feature does not force every non-production engine to pretend it can rewrite persisted encrypted storage.

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
- public `DxtrBox.encryptBox()` plaintext -> encrypted migration
- Dart-side live-handle migration rejection
- correct-key reopen and wrong/missing-key rejection after migration
- data parity before and after migration
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
- explicit plaintext -> encrypted migration
- migration rejection for missing/open/already-encrypted boxes and empty keys
- pre-commit validation failure preserving the original plaintext state

### Global-state test isolation

The engine has process-global base-path, database-cache, watcher, maintenance, and mutation-lock state. Same-process tests must avoid racing global reinitialization. Test-only synchronization is allowed where needed as long as production synchronization semantics are not weakened.

## Migration atomicity coverage

`rust/src/db.rs` validates the migration transaction contract directly. All plaintext values are validated and encrypted before the transaction commits the final `chacha20poly1305` metadata state. A failure before commit must leave the original plaintext box readable.

`test/native_integration_test.dart` validates the public path:

```text
DxtrBox.encryptBox
  -> NativeEncryptionMigrationApi
  -> generated FRB binding
  -> Rust api::encrypt_box
  -> db::encrypt_box
  -> redb transaction
```

The public API rejects migration while a Dart handle is live. After all handles close, a successful migration must reject missing/wrong keys and preserve the original decoded values when reopened with the new key.

A dedicated process-kill test targeted specifically at killing a migration while its transaction is in-flight remains future hardening. The current durability claim is limited to redb transactional before/after semantics plus the existing acknowledged-commit process-crash suite.

## Process-kill durability test

File: `rust/tests/process_crash.rs`

Run with:

```bash
make process-crash
```

This test proves a stronger boundary than ordinary `close()` / reopen coverage:

1. The parent creates a temporary database directory.
2. A child instance of the Rust test executable initializes the directory.
3. The child always opens a plaintext box; builds with the `encryption` feature also open an encrypted box.
4. The child completes several committed transactions.
5. Only after the final committed write returns, the child prints `DXTR_BOX_COMMITTED` and flushes stdout.
6. The parent receives that marker and kills the child process while both boxes remain open.
7. A fresh process context reopens the same files and verifies all previously committed plaintext values plus encrypted values when the `encryption` feature is enabled.

The test deliberately makes **no guarantee for writes that had not returned successfully before termination**. It validates recovery of acknowledged commits, which is the contract dxtr_box should claim at this stage.

## Benchmark smoke harness

Package: `benchmark/`

Test file: `benchmark/test/benchmark_smoke_test.dart`

Comparison dependency: current `hive_ce` line used by the benchmark package.

Run the CI-sized smoke workload:

```bash
make benchmark-smoke
make native-size-stability
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

The benchmark package depends on the root `dxtr_box` package by local path but resolves its own benchmark-only dependencies. This separation is deliberate: benchmark tooling must not silently raise the SDK floor of the library being benchmarked.

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

### Minimum SDK job — Ubuntu

- install Flutter 3.22.0 / Dart 3.4.0
- `flutter pub get` for the root package only
- `flutter analyze`
- `flutter test`

This job is the compatibility contract for the declared lower bound. It intentionally does not resolve the separate benchmark package.

### Current Flutter job — Ubuntu

- install current stable Flutter
- `flutter pub get`
- formatting check, including `benchmark/test`
- `flutter analyze`
- `flutter test`

### FRB generated-bindings job

- install Flutter + Rust
- install `flutter_rust_bridge_codegen 2.8.0`
- regenerate checked-in Dart/Rust bindings
- upload regenerated files as a short-lived artifact for debugging
- fail if `git diff` shows generated binding drift

Native API source changes are therefore incomplete until generated bindings committed to the repository match FRB codegen output.

### Native Linux job

- build the Rust release library
- run Dart -> FRB -> Rust native integration tests from the root package, including explicit encryption migration
- resolve the separate `benchmark/` package on current stable Flutter
- run the `hive_ce` benchmark smoke harness with a deliberately small operation count

The benchmark step is an execution/regression check, not a performance threshold gate.

### Rust host matrix

Runs on:

- Ubuntu
- macOS
- Windows

Each host runs:

- rustfmt check
- clippy with warnings denied on the default/full profile
- minimal tests with `--no-default-features`
- encryption tests with `--no-default-features --features encryption`
- full/default tests

`cargo test --all-targets` includes the process-kill integration test. Minimal validates plaintext acknowledged-commit recovery; encryption/full additionally validate encrypted recovery.

### Native size baseline job

Linux x86_64 builds minimal, encryption, and full release libraries into isolated Cargo target directories and records exact bytes plus toolchain/environment metadata in `native-size-baseline.tsv`. PR #12 CI #144 measured 1,893,736 / 1,992,296 / 2,032,312 bytes respectively. The artifact contains only the TSV metadata file, not Cargo target directories.

### Native size stability job — Linux x86_64

The size job first records the normal minimal/encryption/full release-library baseline, then runs `tool/native_size_stability.sh` with three isolated builds per profile. The job fails if `min_bytes != max_bytes` for any profile on the same commit/toolchain.

CI #151 validated:

- minimal: 3 runs, 1,893,736 bytes each, spread 0;
- encryption: 3 runs, 1,992,296 bytes each, spread 0;
- full: 3 runs, 2,032,312 bytes each, spread 0.

This is a reproducibility gate, not a cross-commit binary-size budget. The artifact retains only `native-size-baseline.tsv` and `native-size-stability.tsv`.

## Platform build validation

The example app is compiled on Android, iOS without code signing, macOS, Linux, and Windows through the existing build matrix/workflows. Native build ownership remains in `rust_builder/`.

## Still not a quality gate

The following remain future hardening work:

- benchmark absolute performance thresholds
- long-duration benchmark trend regression policy
- cross-commit binary-size regression budget/threshold
- dedicated process-kill interruption injection during plaintext -> encrypted migration
- Dart 3.13 native symbol tree-shaking verification (future-only; do not implement now)

Performance CI should remain trend-oriented rather than a brittle absolute timing gate on shared GitHub runners.
