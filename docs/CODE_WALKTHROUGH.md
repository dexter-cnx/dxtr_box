# dxtr_box Code Walkthrough

This walkthrough describes the publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, completed 0.4 hardening gates, PR #34 change-aware CI, and the corrected 0.5 read-path decomposition from PR #33.

## 1. Package boundary

`dxtr_box` is one self-contained Flutter FFI plugin:

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

Platform build mapping:

```text
Android       android/build.gradle -> ../cargokit -> ../rust
iOS/macOS     podspec -> ../cargokit/build_pod.sh -> ../rust
Linux/Windows CMakeLists.txt -> ../cargokit/cmake/cargokit.cmake -> ../rust
```

Stable compatibility:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
```

Exactly three native profiles remain:

```text
minimal
encryption
full
```

Dart 3.13 recorded-use/native tree shaking remains outside current 0.5 work.

## 2. Runtime boundary

```text
Flutter app
  -> DxtrBox / Box / query + migration types
  -> NativeDxtrApi capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lightweight metadata, lifecycle guards, query objects, and Hive CE migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance, and plaintext-to-encrypted migration.

## 3. Storage identity

Each box maps to:

```text
{base_path}/{box_name}.dxtr
```

Core redb tables are `data` and `meta`; `full` additionally maintains persisted index definitions/entries.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

PH-05 guards the public entrypoint and this storage identity so a format change requires explicit backward-read or migration evidence.

## 4. Mutation atomicity

```text
Box.put / putAll / delete / deleteAll / clear
  -> DxtrCodec
  -> FRB
  -> Rust validation
  -> optional encryption
  -> one redb write transaction
  -> primary + index changes
  -> one commit
  -> watch event after commit only
```

Primary data is authoritative. Persisted indexes are derived state and never commit independently from the corresponding primary mutation.

## 5. Production point-read path

`Box.get` currently executes:

```text
Box.get
  -> NativeDxtrApi.get
  -> FrbNativeDxtrApi.get
  -> generated FRB call
  -> Rust api::get
  -> db::get
  -> DATABASES lookup / Arc clone
  -> Database::begin_read
  -> open DATA table
  -> table.get(key)
  -> redb value -> Vec<u8> on hit
  -> optional ChaCha20Poly1305 decrypt/authenticate
  -> validate_message_pack
  -> Vec<u8> through FRB
  -> DxtrCodec.decode
```

`Box.containsKey` executes the same native database lookup/read-transaction/table-open region but stops at `table.get(key).is_some()` and returns a boolean.

Both operations remain authoritative against native storage. Dart metadata cannot replace them without weakening cross-handle/cross-process freshness. No Dart whole-box cache is allowed as a performance shortcut. Encrypted reads retain full AEAD authentication.

## 6. Query execution

`Box.query(BoxQuery)` sends one structured MessagePack query through one FRB call:

```text
Box.query
  -> serialize query AST
  -> one FRB call
  -> one redb ReadTransaction snapshot
  -> optional index candidate narrowing
  -> authoritative primary reads
  -> optional decrypt
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

Persisted indexes narrow candidates only. Every candidate is re-read from primary storage and re-evaluated against the complete predicate. Raw MessagePack scalar byte order is not treated as numeric order. Indexes do not currently satisfy ORDER BY.

## 7. Encryption and native-profile safety

Encrypted boxes can use native scan queries but cannot create persisted plaintext-derived secondary indexes. Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

Exactly three capability profiles remain:

```text
minimal     CRUD + lifecycle + native watch
encryption  minimal + encrypted create/open/read/write
full        encryption + maintenance + query/index
```

Reduced profiles reject indexed boxes they cannot safely maintain.

## 8. Hive CE migration

Core `dxtr_box` has no runtime Hive CE dependency.

Migration flow:

```text
migrateFromHiveCe
  -> validate/enumerate source
  -> key/value conversion
  -> collision detection
  -> DxtrCodec preflight
  -> acquire exclusive destination reservation
  -> create destination
  -> migration-only internal open
  -> one Box.putAll
  -> close
  -> release reservation
```

Ordinary opens are excluded while migration owns the destination. Initialization/write failure cleanup removes migration-owned destination state and releases its marker.

## 9. FRB drift and package gates

Checked-in FRB 2.8 bindings are regenerated when affected or during full validation. Any generated diff fails the binding-current gate. Runtime/codegen/macros remain aligned at 2.8.0.

Package readiness remains:

```text
make package-readiness
  -> dart doc
  -> dart pub publish --dry-run --ignore-warnings
```

The package must remain self-contained; no production dependency may reach outside the package root.

## 10. Native-size policy

Minimal, encryption, and full are measured independently:

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
fail when head_bytes - base_bytes > allowed_growth
```

Intentional growth must be reviewed with measured deltas rather than bypassing the gate.

## 11. Staged published consumers

`tool/validate_published_consumer.dart` stages the consumer-visible package payload, checks required native inputs and repository leakage, creates a fresh Flutter consumer, and builds using only the staged package.

Full validation covers:

```text
Android
iOS
macOS
Linux
Windows
```

PR #34 moved these consumers into the main CI DAG behind Fast CI rather than launching an independent expensive workflow for every early commit.

## 12. Four-engine comparison framework

Benchmark-only adapters compare:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

Correctness is a hard gate. Hosted-runner timing is diagnostic and is not a faster/slower release threshold.

## 13. Change-aware CI — PR #34

The main workflow uses one central classifier and a fast mandatory gate:

```text
change-detection
      |
      v
   Fast CI
      |
      +--> affected expensive validation during Draft iteration
      |
      v
Merge Gate / full quality bar
```

Fast CI runs `make ci-fast`, and local `make preflight` maps to the same cheap gate:

```text
format-check
  -> Dart format
  -> rustfmt
analyze
  -> Flutter analyze
test-fast
  -> codec / Box / public-contract Dart tests
contract-check
  -> public export + dxtr_box/1 verifier
rust-check
  -> clippy
  -> cargo check minimal
  -> cargo check encryption
  -> cargo check full
  -> cheap minimal-profile Rust lib tests
```

Generic formatting/lint runs once on Ubuntu. macOS/Windows Rust jobs focus on platform compilation rather than duplicating rustfmt/clippy.

Draft PRs may use affected CI. Ready-for-review and subsequent non-draft commits run the full quality bar. The terminal protected status is `CI / Merge Gate / full quality bar`.

CI scheduling is infrastructure only. It does not alter native read semantics, storage format, encryption, or benchmark methodology.

See `docs/CI_STRATEGY.md`.

## 14. 0.3 point-read diagnosis

The earlier diagnostic measured approximately:

```text
native plaintext get hit       225.726 us/op
Dart MessagePack decode only     6.018 us/op
native containsKey hit         193.830 us/op
Dart metadata membership         6.532 us/op
```

This established that the composite native-adapter region was material, but it did not separate redb setup, lookup, copy, validation, crypto, FRB transport, or Dart async work.

See `docs/POINT_READ_DIAGNOSIS_03.md`.

## 15. 0.5 PR #33 Rust decomposition harness

`rust/src/read_path_bench.rs` is test-only and its timing test is ignored during ordinary Rust tests. It runs explicitly through:

```bash
make benchmark-read-path
```

Measured Rust operations:

```text
redb_read_transaction_create
redb_read_transaction_open_table
redb_point_lookup_borrowed hit/miss
redb_point_lookup_copy hit
messagepack_validate
vec_payload_copy
decrypt_authenticate
db_get plaintext/encrypted hit/miss
db_contains_key hit/miss
```

Stable-snapshot lookup cases keep the read transaction/table outside the timed closure to separate lookup work from transaction creation. This is diagnostic only and is not a proposal for stale long-lived public read snapshots.

### Public-wire payload correction

The benchmark must model public `DxtrCodec.encode`, not merely any valid MessagePack value.

The original Rust medium workload used `Vec<u8>` for the body. Serde encoded that as a 4,096-element MessagePack sequence, while the Dart benchmark used a 4,096-character string inside the tagged-map codec representation. This artificially inflated native validation cost.

The corrected Rust workload emits the logical public shape:

```text
["@dxtr:map", [["id", id], ["label", label], ["body", string_body]]]
```

Therefore run #7 is superseded for bottleneck selection.

## 16. Dart / FRB decomposition harness

`test/read_path_benchmark_test.dart` measures:

```text
dart_dxtr_codec_decode
native_adapter_get
public_box_get
native_adapter_contains_key
public_box_contains_key
```

The matrix covers small/medium payloads, plaintext/encrypted where applicable, and hit/miss where applicable. Assertions remain outside timed loops.

## 17. Machine-readable benchmark evidence

`make benchmark-read-path` produces:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

Rust receives an absolute repository-root output path because the Cargo unit-test process executes from the crate directory. The Makefile fails if either JSONL file is missing.

The dedicated workflow additionally captures Flutter, Rust, Cargo, runner/kernel, and CPU metadata and uploads `read-path-benchmark-linux-x64`. Evidence upload fails closed when required files are absent.

## 18. Corrected Phase A baseline — run #11

Corrected evidence:

```text
Read-path Benchmark #11
run id:      31949461503
artifact id: 9264234449
head:        09c407139b824c3cbb6ce12f3bd8dacf84d03285
```

Recorded environment:

```text
Ubuntu hosted runner / Linux x86_64
Intel Xeon Platinum 8370C / 4 logical CPUs
Flutter 3.47.0
Dart 3.13.0
rustc 1.97.1
cargo 1.97.1
```

Representative corrected medium medians:

```text
Rust in-process
  transaction + table open       0.567 us
  lookup + copy hit              0.191 us
  MessagePack validation         0.211 us
  full plaintext db_get hit      1.055 us
  decrypt/authenticate           4.952 us
  full encrypted db_get hit      6.056 us

Dart / public path
  native adapter get hit        90.470 us
  public Box.get hit           102.118 us
  DxtrCodec.decode               5.972 us
  native adapter contains hit   74.310 us
  public Box.containsKey hit    74.672 us
```

The corrected native workload no longer shows MessagePack validation as the dominant point-read cost. The earlier ~17.37 us validation result came from the mismatched byte-sequence workload and is superseded.

## 19. Cross-runtime / FRB interpretation

The corrected baseline exposes a structural gap:

```text
medium in-process Rust db_get       ~1.055 us
medium Dart native-adapter get     ~90.470 us
medium public Box.get             ~102.118 us

medium in-process containsKey       ~0.655 us
medium Dart native containsKey     ~74.310 us
medium public containsKey          ~74.672 us
```

This makes the cross-runtime/generated-binding/Dart-async region the highest-priority investigation area for PR 2.

It is **not** a pure FRB timer. The gap can include:

```text
FRB transport/generated call behavior
Dart async scheduling
request/response allocation and conversion
runtime/harness differences
shared-runner noise
```

Do not subtract the medians and publish an exact FRB percentage.

## 20. PR 2 implementation order

PR 2 should proceed in this order:

1. Preserve the corrected public-wire benchmark workload.
2. Add a controlled boundary diagnostic that separates generated-FRB call/transport behavior from Dart async adapter/conversion work without leaving benchmark-only production API surface behind.
3. Inspect generated FRB call mode and request/response allocation/conversion behavior.
4. Select a production single-key optimization only after an actionable cost is isolated.
5. Treat native validation/copy/transaction cleanup as secondary unless new evidence elevates it.
6. Preserve authoritative native `get`/`containsKey`, cross-process freshness, and full AEAD authentication.
7. Leave stale-snapshot/read-session work for its dedicated later phase unless new evidence changes priority.
8. Record controlled before/after evidence for every production optimization.

## 21. 0.5 implementation sequence

```text
PR 1 / #33 — read-path benchmark decomposition                  corrected evidence baseline
PR 2       — single-key read optimization                       next
PR 3       — batch/multi-key read path
PR 4       — read-session investigation / explicit session only if safe
PR 5       — expanded comparison + 0.5 closure audit
```

Future batch reads should target one FRB call plus one redb snapshot for N keys rather than N bridge crossings and N independent transactions, while defining missing/duplicate-key behavior explicitly and supporting encrypted boxes.

## 22. Invariants to preserve

- Dart >=3.4 / Flutter >=3.22.
- FRB exactly 2.8.0.
- Native identity `rust_lib_dxtr_box`.
- Exactly three native profiles.
- `dxtr_box/1` remains readable.
- Primary data authoritative over indexes.
- `get` and `containsKey` authoritative native reads.
- No Dart whole-box cache.
- Full encrypted authentication.
- Query/index/migration correctness.
- Native-size regression policy.
- Five-platform staged consumer builds in full validation.
- Change-aware CI never weakens the final merge quality bar.
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
make native-size-baseline
make native-size-stability
make native-size-regression
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

See `docs/PERFORMANCE_READ_PATH_05.md` for the normative 0.5 evidence record and `docs/CI_STRATEGY.md` for CI execution policy.