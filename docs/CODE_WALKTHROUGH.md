# dxtr_box Code Walkthrough

This walkthrough describes the current publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, the completed 0.4 hardening gates, and the active 0.5 read-path performance work.

## 1. Self-contained package boundary

`dxtr_box` is the single Flutter package and FFI plugin:

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

No consumer build step reaches outside the package root and the root `pubspec.yaml` has no path-dependent native builder.

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

Stable compatibility remains:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
```

Exactly three native capability profiles remain:

```text
minimal
encryption
full
```

Dart 3.13 recorded-use/native tree shaking is outside the 0.5 milestone.

## 3. Storage and lifecycle

Each box maps to:

```text
{base_path}/{box_name}.dxtr
```

Core redb tables are `data` and `meta`. The full profile also maintains `index_definitions` and `index_entries`.

The durable metadata identity includes:

```text
meta[format_version] = dxtr_box/1
```

This remains guarded by the 0.4 public API/storage contract gate.

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

## 5. Point reads — production path

`Box.get` currently executes:

```text
Box.get
  -> NativeDxtrApi.get
  -> FrbNativeDxtrApi.get
  -> generated FRB get_
  -> Rust api::get
  -> db::get
  -> DATABASES lookup / Arc clone
  -> Database::begin_read
  -> open data table
  -> table.get(key)
  -> redb guard -> Vec<u8> copy on hit
  -> optional ChaCha20Poly1305 decrypt/authenticate with record-key AAD
  -> validate_message_pack
  -> Vec<u8> through FRB
  -> DxtrCodec.decode
```

`Box.containsKey` currently executes:

```text
Box.containsKey
  -> NativeDxtrApi.containsKey
  -> FrbNativeDxtrApi.containsKey
  -> generated FRB containsKey
  -> Rust api::contains_key
  -> db::contains_key
  -> DATABASES lookup / Arc clone
  -> Database::begin_read
  -> open data table
  -> table.get(key).is_some()
```

These reads remain authoritative against native storage. The 0.5 milestone must not replace them with Dart metadata or whole-box cache lookups because doing so would weaken cross-handle/cross-process freshness semantics.

Encrypted reads must retain full authentication. MessagePack validation must not be removed merely because Dart decodes the value later unless evidence and a separately justified correctness argument prove a safe alternative.

## 6. 0.3 point-read diagnosis

The previous diagnostic measured approximately on one shared GitHub runner:

```text
native plaintext get hit       225.726 us/op
Dart MessagePack decode only     6.018 us/op
native containsKey hit         193.830 us/op
Dart metadata membership         6.532 us/op
```

The important conclusion was structural rather than absolute: Dart decode was not dominant in that run, while the native adapter region remained composite and undecomposed.

That native region still included:

```text
FRB call/response
redb read transaction setup
redb table open / point lookup
optional decrypt/authenticate
native MessagePack validation
payload allocation/copy
```

Therefore 0.3 deliberately made no production point-read optimization.

See `docs/POINT_READ_DIAGNOSIS_03.md`.

## 7. 0.5 PR 1 — Rust in-process decomposition

`rust/src/read_path_bench.rs` is a `#[cfg(test)]` module and its benchmark test is `#[ignore]`. Ordinary Rust test profiles compile the harness but do not execute the timing loop. `make benchmark-read-path` runs it explicitly in release mode.

It measures these components separately:

### 7.1 Read transaction setup

```text
redb_read_transaction_create
  -> Database::begin_read
```

This isolates transaction creation/setup from table open and lookup.

### 7.2 Transaction plus table open

```text
redb_read_transaction_open_table
  -> Database::begin_read
  -> read.open_table(DATA)
```

The difference from transaction-only timing is an inference for table-open overhead, not a separately instrumented internal redb phase.

### 7.3 Raw point lookup on one stable snapshot

```text
one ReadTransaction
  -> one readable DATA table
  -> repeated table.get(key)
```

Cases:

```text
redb_point_lookup_borrowed / hit
redb_point_lookup_borrowed / miss
```

Because the read transaction and table are held outside the timed per-operation closure, these cases measure lookup work without repeated transaction setup.

This is diagnostic only. It is **not** a proposal to make default public reads use a long-lived snapshot.

### 7.4 Lookup plus redb value copy

```text
redb_point_lookup_copy
  -> table.get(key)
  -> guard.value().to_vec()
```

Comparing borrowed lookup vs copied lookup helps identify the cost of the native payload copy on successful reads.

### 7.5 Native MessagePack validation

```text
messagepack_validate
  -> validate_message_pack(payload)
  -> rmp_serde::from_slice<IgnoredAny>
```

This measures the exact production validation helper on an already available plaintext payload.

### 7.6 Native allocation/copy baseline

```text
vec_payload_copy
  -> payload.to_vec()
```

This gives a standalone allocation/copy baseline independent of redb.

### 7.7 Decrypt/authenticate

With the encryption feature:

```text
decrypt_authenticate
  -> ChaCha20Poly1305
  -> record-key AAD
  -> authenticate + decrypt prepared ciphertext
```

The ciphertext is prepared outside the timed loop so encryption and nonce generation are not included.

### 7.8 Full in-process production database calls

```text
db_get
  plaintext hit/miss
  encrypted hit/miss

db_contains_key
  plaintext hit/miss
```

These call the real production `db::get` / `db::contains_key` implementation without FRB or Dart.

## 8. 0.5 PR 1 — Dart / FRB decomposition

`test/read_path_benchmark_test.dart` uses the production `FrbNativeDxtrApi` and public `Box` facade.

It measures:

```text
dart_dxtr_codec_decode
native_adapter_get
public_box_get
native_adapter_contains_key
public_box_contains_key
```

Matrix dimensions include:

```text
payload: small, medium
mode: plaintext, encrypted where applicable
outcome: hit, miss where applicable
```

Assertions are performed after timed loops rather than inside each operation.

### FRB interpretation

PR 1 deliberately does not add a benchmark-only `echo`/passthrough function to `rust/src/api.rs`, so there is no direct FRB-only timer.

The approximate native-boundary region may be inferred by comparing:

```text
Dart native_adapter_get
minus
Rust db_get
```

or the equivalent contains measurements from the same workflow run.

That difference is **not** a pure FRB percentage. It also contains Dart async adapter work and differences between the Dart and Rust timing harnesses. If the inferred boundary region becomes the likely bottleneck but is too ambiguous to guide PR 2, measure it more directly in a later diagnostic without leaving benchmark plumbing in the shipped API.

## 9. Machine-readable benchmark evidence

Root target:

```text
make benchmark-read-path
```

Default local configuration:

```text
READ_PATH_RUST_ITERATIONS = 2000
READ_PATH_DART_ITERATIONS = 1000
READ_PATH_SAMPLES = 7
```

Outputs:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

Each contains a context row followed by measurement rows with:

```text
operation
payload
mode
outcome
iterations
samples
sample_ns
median_ns_per_op
```

The dedicated `Read-path Benchmark` workflow also captures Flutter, Rust, Cargo, kernel, and CPU metadata and uploads `build/read-path/` as a CI artifact.

Shared-runner timings remain diagnostic; there is no faster/slower performance threshold in PR 1.

## 10. 0.5 evidence classification

### Measured fact

Before the PR 1 artifact completes, the established measurements are still the 0.3 composite observations only.

### Inference

The composite native read region dominated the 0.3 run relative to Dart decode, but the dominant internal component is not yet known.

### Implemented optimization

None in PR 1.

### Deferred idea

Do not implement yet:

- Dart whole-box caching;
- Dart metadata-backed authoritative `containsKey`;
- skipped AEAD authentication;
- skipped native validation without evidence/correctness proof;
- long-lived default read snapshots;
- speculative FRB buffer tricks;
- storage-format changes;
- public multi-key API solely to make a benchmark look better.

See `docs/PERFORMANCE_READ_PATH_05.md`.

## 11. Query execution

`Box.query(BoxQuery)` sends one structured MessagePack query through one FRB call.

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
  -> offset / limit
  -> one response
```

Persisted indexes only narrow candidates. Every candidate is re-read from authoritative primary data and re-evaluated against the complete predicate.

This existing one-snapshot query design is relevant to 0.5 PR 3 because it demonstrates the general shape desired for efficient batch reads without implying that ordinary point reads should use stale long-lived transactions.

## 12. Persisted index planner

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

## 13. Deterministic sorting

`BoxQuery.sortBy` is carried inside the existing query payload. Sorting occurs before pagination and supports nested fields, explicit null/missing placement, numeric/string ordered domains, and record-key ascending as the final deterministic tie-break.

Indexes narrow `where`; they do not currently satisfy ORDER BY.

## 14. Encryption and profile safety

Encrypted boxes can use native scan queries but cannot create persisted secondary indexes yet because plaintext-derived index keys would leak protected values. Plaintext-to-encrypted migration is rejected while persisted indexes exist.

Exactly three Rust capability profiles remain:

```text
minimal     CRUD + lifecycle + native watch
encryption  minimal + encrypted create/open/read/write
full        encryption + maintenance + query/index implementation
```

`full` is the default production build. Reduced profiles reject boxes containing persisted indexes because they cannot safely maintain derived state.

## 15. Hive CE migration

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

Ordinary `DxtrBox.open(destinationName)` checks reservation both before and immediately after native open. Initialization/write failure cleanup removes migration-owned destination state and releases its marker.

## 16. FRB drift gate

Checked-in Flutter Rust Bridge 2.8 bindings are regenerated in CI. Any diff under generated Dart/Rust binding output fails the binding-current job.

PR 1 does not add a new FRB method, so generated bindings should remain unchanged.

## 17. Native-size policy

Minimal, encryption, and full are compared independently under the 0.4 gate:

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
fail when head_bytes - base_bytes > allowed_growth
```

The Rust read-path benchmark module is `#[cfg(test)]`, so it is not intended to become part of release library code. The normal native-size regression gate remains authoritative evidence that PR 1 does not create unacceptable shipped binary growth.

## 18. Package publication readiness

The root package remains self-contained and publishable. `make package-readiness` runs public docs plus `dart pub publish --dry-run --ignore-warnings`.

Benchmark/test files remain development tooling, not public runtime dependencies.

## 19. Local database comparison framework

Comparison-only dependencies and adapters live under `benchmark/`; they are not part of the published runtime package.

The matrix remains:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

Correctness is a hard gate. Timing remains diagnostic.

0.5 PR 5 will extend the matrix with batch/multi-key get and mixed read-heavy workloads after the Dxtr_Box multi-key design is complete.

## 20. Published-payload consumer flow

`tool/validate_published_consumer.dart` stages a consumer-visible package tree and builds fresh Android/iOS/macOS/Linux/Windows consumers using only that staged package boundary.

Performance work must not bypass this gate or introduce repository-relative native assumptions.

## 21. Public API + storage compatibility guard

```text
flutter test
  -> test/public_api_contract_test.dart
     -> compile representative public API
     -> verify public export set
     -> verify format_version / dxtr_box/1
```

PR 1 changes no public Box API and no storage identity. A future PR 3 batch-read API, if adopted, will be a deliberate public API addition and must update public API documentation/tests in the same PR.

## 22. Current milestone and next implementation order

```text
PR 1 — read-path benchmark decomposition
PR 2 — single-key read optimization using PR 1 evidence
PR 3 — batch/multi-key read path
PR 4 — read-session investigation / explicit implementation only if safe
PR 5 — comparison matrix + 0.5 closure audit
```

Preserve these invariants throughout:

- Dart >=3.4 / Flutter >=3.22;
- exact FRB 2.8 alignment;
- native identity `rust_lib_dxtr_box`;
- exactly three native profiles;
- `format_version = dxtr_box/1` unless an explicit compatibility/migration design is reviewed;
- primary data authoritative over indexes;
- authoritative native `get` and `containsKey` semantics;
- cross-process visibility not weakened by Dart cache shortcuts;
- full encrypted authentication;
- query/index/migration behavior remains green;
- comparison timing remains diagnostic rather than a release threshold;
- native-size and five-platform staged-consumer gates remain green;
- performance changes require before/after evidence plus correctness validation.

Important targets:

```text
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
