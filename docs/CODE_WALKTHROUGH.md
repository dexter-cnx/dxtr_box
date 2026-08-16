# dxtr_box Code Walkthrough

This walkthrough describes the publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, completed 0.4 hardening gates, and current 0.5 read-path optimization work.

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

The Flutter package/plugin identity is `dxtr_box`. The native crate/library remains `rust_lib_dxtr_box`.

Platform build mapping:

```text
Android
  android/build.gradle -> ../cargokit -> ../rust

iOS/macOS
  podspec -> ../cargokit/build_pod.sh -> ../rust

Linux/Windows
  CMakeLists.txt -> ../cargokit/cmake/cargokit.cmake -> ../rust
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

Core redb tables are `data` and `meta`; `full` additionally maintains index definitions/entries.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

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

Primary data is authoritative. Persisted indexes are derived state and never commit independently from their primary mutation.

## 5. Production point-read path

`Box.get`:

```text
Box.get
  -> NativeDxtrApi.get
  -> FrbNativeDxtrApi.get
  -> generated FRB
  -> Rust api::get
  -> db::get
  -> DATABASES lookup / Arc clone
  -> Database::begin_read
  -> open DATA table
  -> table.get(key)
  -> redb value -> Vec<u8> copy on hit
  -> optional ChaCha20Poly1305 decrypt/authenticate
  -> validate_message_pack
  -> Vec<u8> through FRB
  -> DxtrCodec.decode
```

`Box.containsKey`:

```text
Box.containsKey
  -> NativeDxtrApi.containsKey
  -> FrbNativeDxtrApi.containsKey
  -> generated FRB
  -> Rust api::contains_key
  -> db::contains_key
  -> DATABASES lookup / Arc clone
  -> Database::begin_read
  -> open DATA table
  -> table.get(key).is_some()
```

These remain authoritative native reads. Dart metadata cannot replace them without weakening cross-handle/cross-process freshness.

No Dart whole-box cache is allowed as a performance shortcut.

Encrypted reads retain full AEAD authentication.

## 6. 0.3 diagnosis

Previous shared-runner evidence measured approximately:

```text
native plaintext get hit       225.726 us/op
Dart MessagePack decode only     6.018 us/op
native containsKey hit         193.830 us/op
Dart metadata membership         6.532 us/op
```

That showed the composite native-adapter region was material but did not isolate redb setup, lookup, copy, validation, crypto, or FRB.

See `docs/POINT_READ_DIAGNOSIS_03.md`.

## 7. 0.5 PR 1 decomposition harness

### Rust in-process harness

`rust/src/read_path_bench.rs` is compiled under `#[cfg(test)]`; its timing test is `#[ignore]` and runs only through:

```bash
make benchmark-read-path
```

Measured components:

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

Stable-snapshot lookup cases keep the read transaction/table outside the timed closure so lookup cost is separated from transaction creation.

This is diagnostic only; it does not imply default public reads should retain long-lived snapshots.

### Dart / FRB harness

`test/read_path_benchmark_test.dart` measures:

```text
dart_dxtr_codec_decode
native_adapter_get
public_box_get
native_adapter_contains_key
public_box_contains_key
```

Matrix dimensions include small/medium payload, plaintext/encrypted where applicable, and hit/miss where applicable.

Assertions are outside timed loops.

## 8. Machine-readable evidence

The root target creates:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

The Rust test receives an absolute repository-root output path because the Cargo unit-test process runs with the Rust crate directory as its working directory. The Makefile fails if either JSONL file is missing.

The GitHub workflow additionally stores:

```text
flutter-version.txt
rust-version.txt
cargo-version.txt
runner.txt
cpu.txt
```

The artifact upload fails closed if evidence is absent.

## 9. 0.5 Phase A baseline — run #7

Successful evidence:

```text
Read-path Benchmark #7
run id:      31947858383
artifact:    read-path-benchmark-linux-x64
artifact id: 9263812713
head:        ec0da61bdd53f70201a31f3c44fddfdfe325a3c8
```

Environment:

```text
Ubuntu 24.04 hosted runner / Linux x86_64
AMD EPYC 9V74 / 4 logical CPUs
Flutter 3.47.0
Dart 3.13.0
rustc 1.97.1
cargo 1.97.1
```

### Rust measured facts

Small payload:

```text
transaction create             0.112 us
transaction + table open       0.395 us
borrowed point lookup hit      0.040 us
lookup + copy hit              0.059 us
MessagePack validation         0.314 us
standalone Vec copy            0.017 us
full plaintext db_get hit      0.875 us
full plaintext db_get miss     0.494 us
full contains hit              0.498 us
decrypt/authenticate           2.273 us
full encrypted db_get hit      3.176 us
```

Medium payload (~4 KiB body):

```text
transaction create             0.113 us
transaction + table open       0.387 us
borrowed point lookup hit      0.106 us
lookup + copy hit              1.650 us
MessagePack validation        17.369 us
standalone Vec copy            0.108 us
full plaintext db_get hit     19.633 us
full plaintext db_get miss     0.545 us
full contains hit              0.554 us
decrypt/authenticate           5.878 us
full encrypted db_get hit     24.204 us
```

For this workload, successful medium native reads are dominated by native MessagePack validation. Copying is secondary. Redb transaction creation/table open is not the dominant cost.

### Dart/public measured facts

Representative run #7 medians:

```text
DxtrCodec.decode
  small                         8.868 us
  medium                        5.908 us

native adapter plaintext get hit
  small                       133.990 us
  medium                       90.866 us

public Box.get plaintext hit
  small                        98.852 us
  medium                      107.654 us

native adapter contains hit
  small                        76.946 us
  medium                       74.524 us

public Box.containsKey hit
  small                        75.272 us
  medium                       81.616 us
```

Some adjacent Dart-layer medians are non-monotonic on the shared runner. They therefore provide end-to-end diagnostic baselines but cannot be added/subtracted as exact component timings.

## 10. FRB interpretation

PR 1 deliberately adds no benchmark-only echo/passthrough endpoint to the production FRB API.

The difference between Dart native-adapter/public timing and in-process Rust timing is **not** a pure FRB timer. It includes:

```text
FRB transport/generated bindings
Dart async scheduling
allocation/conversion
runtime/harness differences
shared-runner noise
```

The cross-runtime region is clearly material as an inference, but do not publish an exact FRB percentage by subtracting unrelated harness medians.

If Phase B targets this region, first add a controlled boundary diagnostic that does not leave benchmark plumbing in the shipped API.

## 11. Phase A decision

Classification:

**Measured fact**
- medium successful native `db_get`: ~19.63 us.
- medium native MessagePack validation: ~17.37 us.
- medium lookup+copy: ~1.65 us.
- transaction+table open: ~0.39 us.
- encrypted authentication is measurable and mandatory.

**Inference**
- FRB/native-adapter/async work is material in public end-to-end reads, but not yet directly isolated.

**Implemented optimization**
- none in PR 1 by design.

**Deferred shortcut**
- no Dart whole cache.
- no metadata-backed authoritative `containsKey`.
- no skipped AEAD authentication.
- no implicit stale long-lived snapshot.
- no speculative bridge rewrite.

## 12. PR 2 implementation order

PR 2 should investigate in this order:

1. Why successful reads perform `validate_message_pack` every time.
2. Whether validation can be made cheaper, deduplicated safely, or restructured without weakening corruption/storage/codec guarantees.
3. Avoidable successful-hit payload copies/allocations.
4. Bridge-boundary measurement only if a production bridge optimization is being considered.
5. Transaction/session reuse only if new evidence justifies it; current evidence does not make it the first target.

A high validation cost is not permission to remove validation. Any change requires a correctness argument plus before/after evidence.

## 13. Query execution

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

This one-snapshot query shape is relevant to future batch reads without implying ordinary point reads should use stale long-lived transactions.

## 14. Persisted-index behavior

Planner-supported comparisons include equality and ordered range predicates. Multiple usable AND predicates can intersect candidate sets.

Persisted indexes only narrow candidates; authoritative records are still re-read and predicates re-evaluated.

Raw MessagePack scalar byte order is not treated as numeric order.

Indexes do not currently satisfy ORDER BY.

## 15. Encryption/profile safety

Encrypted boxes can query via native scans but cannot create persisted plaintext-derived secondary indexes.

Exactly three capability profiles remain:

```text
minimal     CRUD + lifecycle + native watch
encryption  minimal + encrypted create/open/read/write
full        encryption + maintenance + query/index
```

Reduced profiles reject indexed boxes they cannot safely maintain.

## 16. Hive CE migration

Core `dxtr_box` has no runtime Hive CE dependency.

Migration flow preserves source data, preflights key/value conversion and MessagePack encoding, acquires an exclusive destination reservation, creates the destination once, writes through one `putAll`, and performs failure cleanup.

## 17. FRB drift gate

Checked-in FRB 2.8 bindings are regenerated in CI. Any generated Dart/Rust diff fails the binding-current gate.

PR 1 adds no new production FRB method.

## 18. Native-size policy

Profiles are measured independently under:

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
```

The benchmark Rust module is test-only and should not inflate the shipped release library. Native-size CI remains the authoritative gate.

## 19. Package publication readiness

The root plugin remains self-contained and publishable. `make package-readiness` performs Dart docs and pub dry-run validation.

Benchmark tooling remains development-only.

## 20. Comparison framework

The comparison harness remains:

```text
dxtr_box
Hive CE
Sembast
SQLite via sqflite_common_ffi
```

Correctness is a hard gate; timing is diagnostic.

0.5 PR 5 will extend this matrix with batch/multi-key and mixed read-heavy workloads.

## 21. Published-payload consumer flow

`tool/validate_published_consumer.dart` stages the package-visible payload and builds fresh Android/iOS/macOS/Linux/Windows consumers using only the staged package boundary.

Performance work must not bypass this gate.

## 22. Public API / durable-storage compatibility

The current compatibility boundary remains:

```text
package:dxtr_box/dxtr_box.dart
meta key:       format_version
format value:   dxtr_box/1
```

A future public batch-read API is a deliberate public API addition and must update API tests/docs in the same PR.

## 23. Current implementation order

```text
PR 1 — read-path benchmark decomposition                         complete evidence baseline
PR 2 — single-key read optimization                              next
PR 3 — batch/multi-key read path
PR 4 — read-session investigation / explicit implementation only if safe
PR 5 — expanded comparison + 0.5 closure audit
```

Preserve throughout:

- Dart >=3.4 / Flutter >=3.22;
- FRB exactly 2.8.0;
- `rust_lib_dxtr_box` identity;
- exactly three profiles;
- `dxtr_box/1` readability;
- authoritative native reads;
- full encrypted authentication;
- query/index/migration correctness;
- native-size policy;
- five-platform staged consumer builds.

See `docs/PERFORMANCE_READ_PATH_05.md` for the normative 0.5 evidence and decision record.
