# dxtr_box Code Walkthrough

This walkthrough describes the current publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, and the 0.4 production-hardening gates.

## 1. Self-contained package boundary

PH-02 makes `dxtr_box` the single Flutter package and FFI plugin:

```text
dxtr_box/
  lib/                 Dart API + generated FRB bindings
  rust/                Rust crate/library: rust_lib_dxtr_box
  cargokit/            native build integration
  android/
  ios/
  macos/
  linux/
  windows/
  example/
```

The Flutter package/plugin identity is `dxtr_box`. The native Rust crate/library remains `rust_lib_dxtr_box` so FRB/native loading identity does not change.

The previous nested `rust_builder/` package is removed. No consumer build step reaches outside the package root and the root `pubspec.yaml` has no path-dependent native builder.

Platform mapping:

```text
Android
  android/build.gradle -> ../cargokit -> ../rust

iOS/macOS
  {ios,macos}/dxtr_box.podspec
    -> ../cargokit/build_pod.sh
    -> ../rust

Linux/Windows
  {linux,windows}/CMakeLists.txt
    -> ../cargokit/cmake/cargokit.cmake
    -> ../rust
```

## 2. Runtime boundary

```text
Flutter app
  -> DxtrBox / Box / query + migration types
  -> NativeDxtrApi capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lightweight key metadata, lifecycle guards, query objects, and Hive CE migration preflight. Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted-index state, maintenance, and plaintext-to-encrypted migration.

## 3. Storage and lifecycle

Each box maps to:

```text
{base_path}/{box_name}.dxtr
```

Core redb tables are `data` and `meta`. The full profile also maintains `index_definitions` and `index_entries`.

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');
await box.put('theme', 'dark');
final theme = await box.get('theme');
await box.close();
```

Encrypted boxes use the same lifecycle with `encryptionKey`. Plaintext-to-encrypted conversion is explicit.

## 4. Mutation atomicity

```text
Box.put / putAll / delete / deleteAll / clear
  -> DxtrCodec
  -> FRB
  -> Rust validation
  -> optional encryption
  -> redb write transaction
  -> primary + persisted-index changes
  -> one commit
  -> watch event after commit only
```

Primary data is authoritative. Persisted indexes are derived state and are never allowed to commit independently from the corresponding primary mutation.

## 5. Point reads

```text
Box.get
  -> NativeDxtrApi.get
  -> FRB
  -> redb read transaction
  -> optional decrypt/authenticate
  -> native MessagePack validation
  -> bytes through FRB
  -> DxtrCodec.decode
```

Point reads remain authoritative and native-backed. The 0.3 diagnosis did not justify a Dart whole-box cache.

## 6. Query execution

`Box.query(BoxQuery)` sends one structured MessagePack query through one FRB call.

Supported predicate semantics include equality/inequality, ordered comparisons, inclusive `between`, null checks, AND/OR groups, dotted nested fields, exact signed/unsigned integer comparison, and deterministic sorting.

Execution:

```text
Box.query
  -> serialize query AST
  -> one FRB call
  -> decode once
  -> one redb ReadTransaction snapshot
  -> optional persisted-index candidate narrowing
  -> primary reads from same snapshot
  -> optional decrypt
  -> full predicate re-evaluation
  -> semantic sort when requested
  -> record-key ascending final tie-break
  -> offset / limit
  -> one response
```

Persisted indexes only narrow candidates. Every candidate is re-read from authoritative primary data and re-evaluated against the complete predicate.

## 7. Persisted index planner

Planner-eligible comparisons:

```text
equal
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
```

Eligibility applies at the top level or beneath `AND` when an index matches the exact dotted field path. The planner does not narrow through `OR`; `notEqual`, `isNull`, and `isNotNull` remain scan-backed.

For multiple usable predicates under AND, candidate sets are intersected from smallest to largest.

Persisted scalar components use MessagePack bytes. Their raw byte order is not treated as numeric order. Range matching decodes scalar components and applies the semantic comparator.

## 8. Deterministic sorting

`BoxQuery.sortBy` is carried inside the existing query payload. Sorting occurs before pagination and supports nested fields, explicit null/missing placement, numeric/string ordered domains, and record-key ascending as the final deterministic tie-break.

Indexes narrow `where`; they do not currently satisfy ORDER BY.

## 9. Encryption and profile safety

Encrypted boxes can use native scan queries but cannot create persisted secondary indexes yet because plaintext-derived index keys would leak protected values. Plaintext-to-encrypted migration is rejected while persisted indexes exist.

Exactly three Rust capability profiles remain:

```text
minimal     CRUD + lifecycle + native watch
encryption  minimal + encrypted create/open/read/write
full        encryption + maintenance + query/index implementation
```

`full` is the default production build. Reduced profiles reject boxes containing persisted indexes because they cannot safely maintain derived state.

## 10. Hive CE migration

Core `dxtr_box` does not depend on Hive CE at runtime. Applications open the Hive CE source themselves and provide callbacks through `HiveCeMigrationSource`.

Migration flow:

```text
migrateFromHiveCe
  -> validate source
  -> enumerate keys
  -> key/value conversion
  -> collision detection
  -> DxtrCodec preflight
  -> acquire exclusive reservation marker
  -> re-check destination absence
  -> exclusively create destination
  -> migration-only internal open
  -> one Box.putAll
  -> close destination
  -> release reservation
```

Ordinary `DxtrBox.open(destinationName)` checks reservation both before and immediately after native open. If migration acquires ownership while an ordinary open is in flight, that handle is closed and the ordinary open is rejected.

Initialization/write failure cleanup removes migration-owned destination state and releases its marker. A hard process kill may still leave incomplete destination/reservation state; file-level staging/promotion and stale-reservation recovery remain deferred.

Real Hive CE 2.19.3 fixtures are isolated under `tool/hive_ce_migration_fixture/` so they cannot raise the core Dart/Flutter SDK floor.

## 11. FRB drift gate

Checked-in Flutter Rust Bridge 2.8 bindings are regenerated in CI. Any diff under generated Dart/Rust binding output fails the binding-current job.

The Dart runtime dependency remains pinned to FRB 2.8.0 because generated bindings, Dart runtime, Rust runtime, codegen, and macros must remain aligned. The package dry-run ignores pub's broad-constraint advisory warning rather than allowing pub resolution to silently select a newer incompatible FRB runtime.

The package refactor does not rename the native Rust library; generated native loading remains based on `rust_lib_dxtr_box`.

## 12. Native-size policy

0.3 established exact native-size measurement and same-commit reproducibility. PR #27 added the cross-commit gate.

Both base and head are built from committed detached worktrees under the same OS/architecture/rustc/cargo environment. Each of `minimal`, `encryption`, and `full` is compared independently.

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
fail when head_bytes - base_bytes > allowed_growth
```

Evidence is emitted to `build/native-size-regression/native-size-regression.tsv`. Intentional growth must be documented rather than bypassing the gate.

See `docs/NATIVE_SIZE_POLICY_04.md`.

## 13. Package publication readiness

PH-02 adds a separate package gate:

```text
make package-readiness
  -> flutter pub get
  -> dart doc --output build/doc
  -> dart pub publish --dry-run --ignore-warnings
```

CI first verifies the self-contained layout: no `rust_builder/`, Rust/Cargokit present, five platform integration files present, and no dependency using a nested YAML `path:` source.

`.pubignore` removes repository-only CI, benchmark, tests, and development tooling from the publication archive while preserving all native build inputs required by consumers.

A green pub dry-run is not enough by itself. Normal CI still validates minimum SDK, Flutter tests, FRB drift, Rust host matrix, native integration, migration fixtures, and native-size policy. Platform Builds remain the final proof for Android/iOS/macOS/Linux/Windows consumption.

The active preview version is `0.4.0-dev.1`. PH-02 was completed by PR #28 and does not publish anything automatically.

See `docs/PACKAGE_RELEASE_04.md`.

## 14. PH-03 local database comparison

Comparison-only dependencies and adapters live under `benchmark/`; they are not part of the published runtime package.

The initial matrix is:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

`benchmark/lib/local_database_adapters.dart` normalizes only the narrow operations needed by the matrix: open/close/destroy, put/putAll, get, containsKey, and deleteAll. It is test infrastructure, not a proposed public database abstraction.

Correctness flow:

```text
shared payload set
  -> open each engine
  -> batch insert
  -> overwrite one record
  -> existing/missing contains checks
  -> delete deterministic subset
  -> close + reopen
  -> verify deletes and retained values
  -> compare final canonical snapshot across engines
```

A mismatch fails CI.

Diagnostic flow:

```text
for each scenario
  -> one warmup per engine
  -> three measured samples
  -> median/min/max
  -> print DXTR_BOX_COMPARISON JSON
  -> optional JSONL artifact
```

Scenarios are `sequential_put`, `batch_put`, `point_get`, `contains`, `delete_all`, and `reopen_read`. No faster/slower threshold exists. Hosted runner timing remains diagnostic evidence only.

CI writes `benchmark/build/comparison/local-database-comparison.jsonl` and uploads the `local-database-comparison` artifact.

See `docs/LOCAL_DATABASE_COMPARISON_04.md`.

## 15. Current milestone

0.3 query/index + Hive CE migration is closed. PH-01 native-size regression policy is complete in PR #27. PH-02 self-contained package/publication hardening is complete in PR #28. PH-03 broader local-database comparison is active in PR #29.

Preserve these invariants:

- Dart >=3.4 / Flutter >=3.22;
- stable native identity `rust_lib_dxtr_box`;
- exactly three Rust capability profiles;
- primary data authoritative over indexes;
- one redb read snapshot per declarative query;
- full predicate re-evaluation after index narrowing;
- deterministic sorting semantics;
- encrypted-index leakage prevention;
- migration reservation ownership and ordinary-open exclusion;
- self-contained publishable package topology;
- comparison timing remains diagnostic rather than a release threshold;
- hardening must not trade away correctness, durability, encryption, or compatibility.

Important targets:

```text
make preflight
make package-readiness
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make benchmark-comparison-correctness
make benchmark-comparison
make benchmark-query-index
make diagnose-point-read
make rust-check
make native-size-baseline
make native-size-stability
make native-size-regression
make example-android
make example-ios
make example-macos
make example-linux
make example-windows
```
