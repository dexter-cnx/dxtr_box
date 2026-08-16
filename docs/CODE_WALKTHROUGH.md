# dxtr_box Code Walkthrough

This walkthrough describes the current publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, the completed 0.4 production-hardening gates, and the change-aware CI topology.

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

The durable metadata identity currently includes:

```text
meta[format_version] = dxtr_box/1
```

This is guarded by PH-05 so a format change requires an explicit compatibility/migration decision rather than a silent constant edit.

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

Point reads remain authoritative and native-backed. `containsKey` is also authoritative native state. The 0.3/0.5 performance work must not introduce a misleading Dart whole-box cache.

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

Checked-in Flutter Rust Bridge 2.8 bindings are regenerated only when the affected policy requires it or during full merge validation. Any diff under generated Dart/Rust binding output fails the binding-current job.

The Dart runtime dependency and codegen remain pinned to FRB 2.8.0 because generated bindings, Dart runtime, Rust runtime, codegen, and macros must remain aligned. CI caches only the versioned codegen binary; it does not cache generated native artifacts in a way that can hide ABI/profile changes.

The separate `FRB Probe` workflow is manual diagnostic tooling. The package refactor does not rename the native Rust library; generated native loading remains based on `rust_lib_dxtr_box`.

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

PH-02 adds a package gate:

```text
make package-readiness
  -> flutter pub get
  -> dart doc --output build/doc
  -> dart pub publish --dry-run --ignore-warnings
```

CI first verifies the self-contained layout: no `rust_builder/`, Rust/Cargokit present, five platform integration files present, and no dependency using a nested YAML `path:` source.

`.pubignore` removes repository-only CI, benchmark, tests, and development tooling from the publication archive while preserving all native build inputs required by consumers.

The active preview version is `0.4.0-dev.1`. PH-02 was completed by PR #28 and does not publish anything automatically.

See `docs/PACKAGE_RELEASE_04.md`.

## 14. PH-03 local database comparison

Comparison-only dependencies and adapters live under `benchmark/`; they are not part of the published runtime package.

The matrix is:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

`benchmark/lib/local_database_adapters.dart` normalizes only the narrow operations needed by the matrix: open/close/destroy, put/putAll, get, containsKey, and deleteAll. It is test infrastructure, not a proposed public database abstraction.

Correctness converges each engine on the same post-reopen snapshot and fails CI on mismatch. Diagnostic timing has no faster/slower threshold. Hosted runner timing remains evidence only.

PH-03 was completed by PR #29. See `docs/LOCAL_DATABASE_COMPARISON_04.md`.

## 15. PH-04 staged published consumer flow

`dart pub publish --dry-run` validates package metadata and lists intended files, but it does not prove a consumer app can native-build using only the publication boundary. PH-04 adds that proof.

`tool/validate_published_consumer.dart`:

```text
repository root
  -> read explicit .pubignore rules
  -> recursively copy while pruning ignored/hidden directories
  -> build/published-payload/dxtr_box
  -> verify required Dart/Rust/Cargokit/platform inputs
  -> reject repository-only leakage
  -> reject root path-source dependencies
  -> flutter create fresh consumer
  -> dependency: ../published-payload/dxtr_box
  -> import package:dxtr_box/dxtr_box.dart
  -> flutter pub get
  -> native platform build
```

The recursive copy deliberately prunes ignored directories before descending. The validator accepts only explicit `.pubignore` file/directory rules; unsupported wildcard/negation syntax fails closed.

Five staged-consumer builds still cover Android, iOS, macOS, Linux, and Windows. They now live inside the main CI DAG behind Fast CI instead of an independently-triggered workflow. PH-04 completed in PR #30.

See `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md`.

## 16. PH-05 public API + storage compatibility guard

PH-05 protects compatibility boundaries without hashing implementation files.

```text
flutter test
  -> test/public_api_contract_test.dart
     -> compile public constructors/enums/typedefs
     -> compile typed Box/DxtrBox/migration signatures
     -> verifyPublicStorageContract()
        -> exact package entrypoint export set
        -> rust/src/db.rs format_version key
        -> rust/src/db.rs dxtr_box/1 marker
```

This catches removals/incompatible signature changes through normal Dart compilation and catches accidental entrypoint or durable-format drift explicitly. Internal implementation refactors remain free to change when the consumer contract is preserved.

The standalone check is:

```bash
dart run tool/verify_public_storage_contract.dart
```

A deliberate 0.x public API change may update the contract in the same reviewed PR. A storage-format change has a higher bar: old-format readability or an explicit migration path, failure/rollback semantics, encryption/index compatibility, previous-format fixtures, and release documentation must accompany the change.

PH-05 is a review/change-control gate; it does not claim that the pre-1.0 API or storage format is already stable. PH-05 completed in PR #31 after the contract passed the minimum Flutter 3.22.0 / Dart 3.4.0 CI job and the normal five-platform staged-consumer matrix.

See `docs/PUBLIC_API_STORAGE_CONTRACT_04.md`.

## 17. Change-aware CI execution

The main workflow now has one central change classifier and one fast mandatory gate:

```text
change-detection
      |
      v
   Fast CI
      |
      +--> minimum SDK
      +--> full Dart tests
      +--> three Rust profiles
      |       +--> macOS/Windows platform compilation
      +--> native integration
      +--> storage/migration/query regression
      +--> FRB drift
      +--> package/publication readiness
      +--> native-size
      +--> five staged consumers
      +--> benchmark correctness/diagnostic smoke
                  |
                  v
        Merge Gate / full quality bar
```

The detector exports the domains `docs`, `dart_core`, `rust_core`, `encryption`, `ffi`, `durable_storage`, `packaging`, `platform`, `native_size`, `benchmark`, and `ci`, plus public-API and per-platform refinements.

Fast CI runs `make ci-fast`, which is also the basis of local `make preflight`:

```text
format-check
  -> Dart format check
  -> cargo fmt --check
analyze
  -> flutter analyze
test-fast
  -> codec/Box/public contract Dart tests
contract-check
  -> public export + format_version/dxtr_box/1 verifier
rust-check
  -> rustfmt
  -> clippy
  -> cargo check minimal
  -> cargo check encryption
  -> cargo check full
  -> cheap minimal-profile Rust lib tests
```

Generic formatting/lint is therefore performed once on Ubuntu. macOS/Windows Rust jobs focus on cross-platform compilation rather than repeating rustfmt/clippy.

Draft PRs use affected CI. Ready-for-review and every later non-draft commit set full validation, so all expensive quality gates must succeed. The stable protected-branch status should be `CI / Merge Gate / full quality bar`; the terminal job rejects skipped jobs in full mode and rejects any failed/cancelled affected job in selective mode.

This is infrastructure scheduling only. It does not change current 0.5 point-read implementation or benchmark semantics.

See `docs/CI_STRATEGY.md`.

## 18. Current milestone

0.3 query/index + Hive CE migration is closed. PH-01 native-size policy, PH-02 package hardening, PH-03 comparison evidence, PH-04 staged published-consumer validation, and PH-05 public API + durable storage contract guarding are complete. The CI optimization is a focused infrastructure PR and must remain separate from PR #33 read-path production/benchmark semantics.

Preserve these invariants:

- Dart >=3.4 / Flutter >=3.22;
- exact FRB 2.8 alignment;
- stable native identity `rust_lib_dxtr_box`;
- exactly three Rust capability profiles;
- primary data authoritative over indexes;
- authoritative native `get` and `containsKey`;
- one redb read snapshot per declarative query;
- full predicate re-evaluation after index narrowing;
- deterministic sorting semantics;
- encrypted-index leakage prevention and authenticated encrypted reads/writes;
- migration reservation ownership and ordinary-open exclusion;
- self-contained publishable package topology;
- comparison timing remains diagnostic rather than a release threshold;
- publication-boundary validation fails closed rather than approximating unsupported ignore rules;
- `format_version = dxtr_box/1` cannot change without explicit compatibility/migration evidence;
- public API drift must be an intentional reviewed contract change;
- hardening/CI optimization must not trade away correctness, durability, encryption, or compatibility;
- Dart 3.13 recorded-use/native tree shaking remains deferred.

Important targets:

```text
make format-check
make rust-check
make analyze
make test-fast
make ci-fast
make preflight
make package-readiness
dart run tool/verify_public_storage_contract.dart
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make benchmark-comparison-correctness
make benchmark-comparison
make benchmark-query-index
make diagnose-point-read
make native-size-baseline
make native-size-stability
make native-size-regression
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```
