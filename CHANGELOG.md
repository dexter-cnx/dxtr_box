## 0.4.0-dev.1

- Started the 0.4 production-hardening milestone.
- Converted `dxtr_box` into a self-contained Flutter FFI plugin: Dart API, Rust crate, Cargokit, and Android/iOS/macOS/Linux/Windows integration now live in one publishable package.
- Removed the internal `rust_lib_dxtr_box` path dependency and nested `rust_builder` package topology.
- Added controlled cross-commit native-size regression gating for the `minimal`, `encryption`, and `full` native profiles.
- Added API-documentation generation and `dart pub publish --dry-run` package-readiness gates.
- Added a curated pub.dev package payload through `.pubignore`.
- Preserved the Dart >=3.4 / Flutter >=3.22 compatibility floor and the stable native library name `rust_lib_dxtr_box`.

## 0.3.0

- Added declarative native queries, persisted scalar indexes, equality/range planning, nested-field indexes, and multi-index `AND` intersection.
- Added deterministic native sorting before pagination and one-redb-read-snapshot query execution.
- Added query/index and point-read diagnostic harnesses.
- Added Hive CE 2.19.3 migration through an isolated fixture package, including encrypted source/destination coverage and exclusive migration destination reservation.
- Closed migration races between concurrent migrations and ordinary `DxtrBox.open()` calls.

## 0.2.0

- Added native encryption with Argon2 + ChaCha20Poly1305 and explicit plaintext-to-encrypted migration.
- Added native cross-handle watch fan-out and durability/process-crash coverage.
- Split native build capabilities into `minimal`, `encryption`, and `full` profiles.
- Added reproducible native-size baseline and same-commit stability measurement.

## 0.1.0

- Initial redb-backed CRUD engine.
- Thin Dart Box API.
- MessagePack dynamic codec.
- Five-desktop/mobile-platform plugin metadata.
- Added Dart `Box`/`DxtrBox` behavioral tests with a fake native boundary.
- Expanded real-redb Rust tests for persistence, atomic validation, invalid names, and delete-box behavior.
- Added deterministic isolation for tests that mutate process-global Rust engine state.
- Added GitHub Actions CI for Flutter format/analyze/test and Rust host-matrix fmt/clippy/tests.
- Added code walkthrough and testing-strategy documentation.
- Added `docs/HIVE_FUNCTIONAL_PARITY.md` and made completion of the Hive/Hive CE functional-parity audit a 1.0 release gate.
