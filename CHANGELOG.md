## 1.0.0

- Declared the existing `dxtr_box` public/package/durable contracts stable after the 0.10 evidence milestone and the 1.0 stabilization sequence.
- Added stronger release guards for the Dart export boundary, Rust root/wildcard API surface, Cargo package/lib identity, native crate type, exact dependency/profile requirements, and `dxtr_box/1` durable format markers.
- Added public API semantic regression coverage for query-model validation, immutable AST snapshots, mixed AND/OR left associativity, explicit `andGroup`/`orGroup` grouping, sort/null ordering, and pagination validation.
- Strengthened staged published-consumer validation so generated Android, iOS, macOS, Linux, and Windows host apps compile representative public `BoxStore`, compatibility `DxtrBox`, query/index, and Hive CE migration surfaces from the publishable payload.
- Confirmed release-candidate persistence/reopen, encrypted reopen and key rejection, migration lifecycle, FRB reproducibility, native profile, native-size, package/pub dry-run, benchmark correctness, and platform-consumer evidence.
- Kept the durable format at `dxtr_box/1`; 1.0.0 introduces no storage migration, query-engine rewrite, encryption redesign, runtime cache, GPUI dependency, Tokio commitment, ORM/codegen layer, sync layer, or fourth native profile.
- Synchronized release audit, project handoff, code walkthrough, README status, and package version for the stable 1.0.0 release.

## 0.10.0-dev.1

- Added deterministic application-shaped workload fixtures for settings/session, catalog/workspace, and activity/event scenarios.
- Added equivalent Dart/FRB and Rust-native real-world scenario runners with correctness validation before timing and machine-readable JSONL output.
- Mirrored fixture shapes and deterministic payloads across frontends so cross-frontend evidence measures equivalent records and logical operation mixes.
- Added a reproducible `tool/real_world_workloads.sh` evidence runner that records Rust/Cargo/Flutter/Dart toolchain metadata and emits three scenario records per frontend.
- Added the `Real-world Workloads` CI workflow with retained evidence artifacts and production-path triggers for `lib/**` and `rust/src/**` changes.
- Kept real-world workload results diagnostic rather than marketing leaderboard claims and preserved the authoritative Rust/redb engine, `dxtr_box/1`, Dart >=3.4, Flutter >=3.22, flutter_rust_bridge 2.8.0, redb 2.1.0, and exactly `minimal | encryption | full` native profiles.
- Synchronized README, project handoff, code walkthrough, release audit, workload documentation, and package version for the 0.10 closure.

## 0.9.0-dev.1

- Added a reusable cross-frontend `StorageBoxContract` conformance kit covering shared CRUD, batch-read ordering/duplicate/miss semantics, key enumeration, deletion, clear, and final empty-state behavior across Rust-native and FRB-adapter frontends.
- Added full-profile index lifecycle correctness guards proving dynamic create/list/drop/reopen semantics remain shared across frontends without introducing schema registration.
- Rejected a speculative persisted schema/index configuration fingerprint because persisted `index_definitions` already are authoritative and there is no independent desired-schema manifest or reconciliation pass for a fingerprint to accelerate.
- Added reproducible startup/reopen diagnostics across 0/1,000/10,000 records and 0/1/4 persisted indexes, recording first-open, p50, p95, and max reopen latency.
- Recorded hosted Linux x64 evidence with reopen p95 below 1 ms across the tested matrix and intentionally added no startup cache, startup fast path, or new durable metadata.
- Hardened the startup benchmark so caller-supplied roots are treated only as parents and zero benchmark iterations are rejected.
- Synchronized README, code walkthrough, project handoff, release audit, and package version for the 0.9 closure while preserving `dxtr_box/1`, Dart >=3.4, Flutter >=3.22, flutter_rust_bridge 2.8.0, redb 2.1.0, and exactly `minimal | encryption | full` native profiles.

## 0.8.0-dev.1

- Established one authoritative Rust storage/query core with two frontends: the existing Flutter/Dart API through flutter_rust_bridge and a first-class native Rust API that links directly to the shared core.
- Added native Rust `DxtrBox` / `BoxHandle` lifecycle, CRUD, batch reads, query/sort/pagination, persisted-index operations, profile-aware encryption support, and structured `DxtrBoxError` results without wrapping Dart/FRB.
- Preserved one `dxtr_box/1` durable format and the existing `.dxtr` files across both frontends; no Rust-only storage format or conversion layer was introduced.
- Validated `minimal`, `encryption`, and `full` native profiles plus `Send + Sync`, multi-threaded same-box mutations, shared-handle lifecycle, encrypted reopen behavior, and full-profile query/index behavior.
- Added an external-consumer-style native Rust example and kept the native API synchronous without imposing Tokio or adding GPUI as a dependency.
- Added bidirectional cross-frontend compatibility tests: Rust-native write -> FRB-adapter read and FRB-adapter put -> Rust-native read on the same physical database files.
- Added reproducible Rust-native vs Dart/FRB diagnostic workloads for point `get`, 100-key batch reads, and indexed query + sort + limit, emitting JSONL evidence with explicit non-marketing interpretation rules.
- Synchronized README, project handoff, code walkthrough, release audit, and package version for the 0.8 closure.
- Preserved Dart >=3.4 / Flutter >=3.22, flutter_rust_bridge 2.8.0, redb 2.1.0, native library `rust_lib_dxtr_box`, and exactly `minimal | encryption | full` native profiles.

## 0.7.0-dev.1

- Added fluent query authoring over the existing `BoxQuery` / `QueryFilter` AST with `BoxQueryBuilder.where(...)` and collision-free `box.queryWhere(...)` while preserving legacy `Box.where(predicate)`.
- Added fluent equality/inequality, ordered comparisons, `between`, null checks, boolean chaining, and explicit groups with left-associative mixed `AND` / `OR` semantics.
- Added `orderBy`, `offset`, `limit`, and bound terminal `find()` ergonomics. Standalone builders remain AST-only and intentionally expose `build()` but not `find()`.
- Added optional `BoxField<T>` typed field-path metadata, including `queryWhereField`, `andField`, `orField`, `orderByField`, and typed fields inside explicit groups. Typed metadata remains schema-free and codegen-free.
- Kept string-path query APIs first-class and verified typed/string/direct-AST paths compile to the same existing query representation and Rust execution path.
- Introduced functional primary API names including `BoxStore`, `BoxCodec`, `NativeBoxApi`, `FrbNativeBoxApi`, `UnavailableNativeBoxApi`, and `BoxStoreMigrationInternals`.
- Retained `DxtrBox`, `DxtrCodec`, and old native seam names only where source compatibility requires deprecated shims; new examples/documentation use functional names.
- Preserved package/durable identities including `dxtr_box`, `rust_lib_dxtr_box`, `.dxtr`, `dxtr_box/1`, and existing `@dxtr:*` durable wire tags.
- Preserved the existing Rust planner, persisted-index behavior, encrypted equality-index contract, encrypted range scan fallback, direct `Box.query(BoxQuery)` API, and authoritative primary-record rechecks.
- Preserved Dart >=3.4 / Flutter >=3.22, flutter_rust_bridge 2.8.0, redb 2.1.0, and exactly `minimal | encryption | full` native profiles.
- Added 0.7 release/compatibility closure documentation and kept the next Rust-native multi-frontend architecture milestone deferred until 0.7 is merged cleanly.

## 0.6.0-dev.1

- Repositioned Dxtr_Box clearly as its own native local database for Flutter rather than a Hive/Hive CE replacement; Hive CE remains an optional migration source, compatibility reference, and benchmark peer.
- Added encrypted persisted equality indexes under the `full` profile using deterministic 256-bit BLAKE2b keyed MAC tokens derived from authenticated box key material and domain-separated by index name and field.
- Kept encrypted primary records authoritative: every encrypted-index candidate is re-read from primary storage, ChaCha20Poly1305 authenticated/decrypted, and fully predicate-checked before returning results.
- Kept encrypted ordered/range predicates (`>`, `>=`, `<`, `<=`, `between`) scan-backed instead of introducing order-preserving/order-revealing encrypted state.
- Added regression coverage for encrypted equality lifecycle/mutation/reopen behavior, encrypted range scan equivalence, and mixed equality + range predicates.
- Preserved transactional primary/index maintenance, `dxtr_box/1`, Dart >=3.4 / Flutter >=3.22, flutter_rust_bridge 2.8.0, redb 2.1.0, native library `rust_lib_dxtr_box`, and exactly `minimal | encryption | full` native profiles.
- Retained the 0.5 authoritative point-read and one-snapshot `Box.getAll` semantics; no Dart whole-box cache or reusable stale read session was introduced.
- Added a dedicated 0.6 release audit tying milestone closure to the full merge quality bar, including API/storage, migration, crash-reopen, native-size, package, benchmark correctness, and five-platform consumer validation.

## 0.5.0-dev.1

- Optimized authoritative single-key reads by moving only native `get` and `containsKey` FRB entrypoints to synchronous generated dispatch while keeping the public Dart API asynchronous.
- Added `Box.getAll(Iterable<String>)` for one-crossing, one-redb-snapshot multi-key reads with explicit order, missing-key, duplicate-key, empty-input, and encrypted-authentication semantics.
- Added decomposed Rust/Dart/FRB read-path diagnostics plus a dedicated 10/100/1000-key batch benchmark.
- Recorded evidence-backed rejection of a reusable long-lived read-session API for 0.5; ordinary reads continue to open fresh authoritative snapshots instead of introducing stale cross-call semantics.
- Preserved Dart >=3.4 / Flutter >=3.22, `flutter_rust_bridge` 2.8.0, native library `rust_lib_dxtr_box`, exactly three native profiles, and storage format `dxtr_box/1`.
- Retained full correctness, migration/query/index, native-size, package, and five-platform staged-consumer validation as merge gates.

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
