# dxtr_box Testing Strategy

The test suite is layered so failures identify whether the problem is in Dart behavior, serialization, native storage, or cross-platform compilation.

## Local commands

Run the Dart/Flutter checks:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test example
flutter analyze
flutter test --reporter expanded
```

Run the Rust checks:

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

Coverage:

- metadata hydration during `DxtrBox.open()`
- key metadata updates after put/delete/clear
- put/get/containsKey
- missing-key default values
- putAll
- where predicates over decoded values
- watch(key:) filtering
- clear event forwarding
- idempotent close
- closed-box guards
- unsafe box-name rejection
- deleteBox/boxExists delegation

The fake is a test seam only. It does not replace native integration tests.

## Rust engine tests

File: `rust/src/db.rs`

These tests use real temporary directories and real redb database files.

Coverage:

- CRUD round trip
- contains-key behavior
- write-transaction clear
- persistence across close/reopen
- putAll pre-validation before write
- invalid box-name rejection
- delete-box file/cache behavior

### Global-state test isolation

The engine has process-global `BASE_PATH` and database-cache state. Rust's test runner may execute tests concurrently, so engine tests acquire a test-only mutex before reinitializing global state. This keeps the production synchronization model unchanged while preventing flaky tests.

## CI

Workflow: `.github/workflows/ci.yml`

Current required-quality intent:

### Flutter job — Ubuntu

- checkout
- install stable Flutter
- `flutter pub get`
- formatting check
- `flutter analyze`
- `flutter test`

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

This gives early host-compiler coverage for the Rust crate even before Flutter platform scaffolds are committed.

## Not yet a green gate

The following checks are intentionally deferred until the FRB adapter and plugin platform directories are checked in:

- `flutter_rust_bridge_codegen generate` diff check
- Android plugin build
- iOS plugin build
- macOS plugin build
- Linux plugin build
- Windows plugin build
- native integration tests against generated bindings
- crash/reopen process-level ACID test
- binary-size regression measurement
- Dart 3.13 native symbol tree-shaking check

Do not mark Milestone 0.1.0 complete from unit tests alone. The milestone requires generated bridge code plus real native build/smoke validation.

## Planned integration-test tiers

### Tier 1 — FRB bridge contract

Once generated bindings are wired, add tests that create a temporary native database and verify Dart -> FRB -> Rust -> redb -> Dart round trips.

### Tier 2 — platform smoke

Build and launch the example on each supported native platform. Exercise init/open/put/get/delete/close/reopen.

### Tier 3 — durability

Use a helper process that writes committed data, terminates, then launches a fresh process to verify committed values. Add controlled interruption scenarios without claiming guarantees beyond redb's documented transaction behavior.

### Tier 4 — performance and size

Benchmark representative workloads against hive_ce and track release artifact size for:

- minimal CRUD
- CRUD + encryption
- full feature set

Performance CI should be trend-oriented rather than a brittle absolute timing gate on shared GitHub runners.
