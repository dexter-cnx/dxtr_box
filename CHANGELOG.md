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
