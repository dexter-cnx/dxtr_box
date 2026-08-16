# dxtr_box Code Walkthrough

This walkthrough describes the publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, completed 0.4 hardening, change-aware CI, and the 0.5 PR1/PR2 read-path work.

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

Stable compatibility:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
```

Dart 3.13 recorded-use/native tree shaking remains deferred.

## 2. Runtime boundary

```text
Flutter app
  -> DxtrBox / Box / query + migration types
  -> NativeDxtrApi capability seam
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lightweight metadata, lifecycle guards, query objects and Hive CE migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance and plaintext-to-encrypted migration.

## 3. Storage identity

Each box maps to `{base_path}/{box_name}.dxtr`.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

Core tables are `data` and `meta`; `full` additionally maintains persisted index definitions and entries.

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

Primary data is authoritative. Persisted indexes are derived state.

## 5. Production point-read path after PR #35

Public Dart API remains asynchronous:

```text
Box.get
  -> NativeDxtrApi.get : Future<Uint8List?>
  -> FrbNativeDxtrApi.get
  -> generated FRB sync call
  -> Rust api::get #[frb(sync)]
  -> db::get
  -> redb read transaction + DATA lookup
  -> optional ChaCha20Poly1305 decrypt/authenticate
  -> validate_message_pack
  -> Vec<u8> through FRB
  -> DxtrCodec.decode
```

`Box.containsKey` follows the same authoritative native path but stops at the point lookup and returns a boolean. Rust `contains_key` also uses `#[frb(sync)]`.

Only these tiny single-key read entrypoints use synchronous FRB dispatch. Query, scans, mutations, migration and other heavier operations keep their existing asynchronous call modes.

No Dart whole-box cache, metadata-backed authoritative shortcut or long-lived stale read snapshot was introduced. Cross-handle/cross-process freshness and encrypted AEAD authentication remain intact.

## 6. Why sync FRB is safe here

PR1 showed the actual in-process native point-read work is very small on the diagnostic workload:

```text
medium plaintext db_get       ~1.055 us
medium db_contains_key        ~0.655 us
```

PR2 then isolated FRB `NormalTask` scheduling as the dominant cost. The scope is deliberately limited to point reads so expensive query/scan/mutation work is not moved onto the Dart isolate synchronously.

## 7. PR2 boundary benchmark

`test/read_path_boundary_benchmark_test.dart` measures generated FRB calls separately from the Future-based adapter.

Pre-change representative medians:

```text
generated FRB get NormalTask          ~226 us/op
generated FRB containsKey NormalTask  ~197 us/op
```

Post-change Read-path Benchmark #24 (`31954326856`):

```text
generated FRB get sync hit           4.312 us/op
generated FRB get sync miss          1.888 us/op
generated FRB containsKey sync hit   2.570 us/op
generated FRB containsKey sync miss  1.734 us/op
native adapter get async hit        21.076 us/op
native adapter contains async hit   17.636 us/op
```

Direct generated-FRB latency improved by roughly 52x for `get` and 77x for `containsKey`. Hosted-runner timing remains diagnostic.

## 8. Existing decomposed read-path harness

`rust/src/read_path_bench.rs` measures:

```text
redb_read_transaction_create
redb_read_transaction_open_table
redb_point_lookup_borrowed
redb_point_lookup_copy
messagepack_validate
vec_payload_copy
decrypt_authenticate
db_get
db_contains_key
```

`test/read_path_benchmark_test.dart` measures:

```text
dart_dxtr_codec_decode
native_adapter_get
public_box_get
native_adapter_contains_key
public_box_contains_key
```

The Rust benchmark payload models the same logical `DxtrCodec` tagged-map wire shape as the Dart workload. The earlier mismatched `Vec<u8>` medium payload is superseded and must not be used for bottleneck decisions.

## 9. Machine-readable evidence

`make benchmark-read-path` produces:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

PR2 adds:

```text
build/read-path/dart-boundary.jsonl
```

The dedicated workflow uploads runner/toolchain metadata with the evidence and fails closed when required files are missing.

## 10. Query execution

`Box.query(BoxQuery)` remains one structured query through one asynchronous FRB call:

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

Persisted indexes narrow candidates only; they do not replace predicate re-evaluation and do not satisfy ORDER BY.

## 11. Encryption/profile safety

Encrypted boxes can use native scan queries but cannot create persisted plaintext-derived secondary indexes. Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

Profiles remain exactly:

```text
minimal
encryption
full
```

Reduced profiles reject indexed boxes they cannot safely maintain.

## 12. Hive CE migration

Core `dxtr_box` has no runtime Hive CE dependency.

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

Ordinary opens are excluded while migration owns the destination. Failure cleanup removes migration-owned state and releases its reservation.

## 13. FRB drift and package gates

Checked-in bindings are generated with FRB 2.8.0. Full CI regenerates them and fails on any diff.

Package readiness remains:

```text
make package-readiness
  -> dart doc
  -> dart pub publish --dry-run --ignore-warnings
```

## 14. Native-size policy

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
```

Minimal, encryption and full are measured independently.

## 15. Staged published consumers

`tool/validate_published_consumer.dart` validates the consumer-visible package payload on:

```text
Android
iOS
macOS
Linux
Windows
```

PR #35 full validation passed all five staged consumers.

## 16. Change-aware CI

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

`make preflight` mirrors Fast CI:

```text
format-check
analyze
test-fast
contract-check
rust-check
```

Full PR #35 rerun `31954326887` passed Fast CI, minimum SDK, Dart full tests, Rust profiles/cross-platform, native integration, storage/migration/query regressions, FRB drift, package readiness, native-size, benchmark smoke, all five staged consumers and the final Merge Gate.

## 17. 0.5 implementation sequence

```text
PR 1 / #33 — read-path decomposition + corrected baseline      complete
PR 2 / #35 — sync FRB single-key reads                         complete / ready to merge
PR 3       — batch/multi-key read path                         next
PR 4       — read-session investigation                        planned
PR 5       — expanded comparison + 0.5 closure audit          planned
```

PR3 should target one FRB call plus one redb snapshot for N keys instead of N independent point-read crossings. It must define missing/duplicate-key behavior and support encrypted boxes.

## 18. Invariants to preserve

- Dart >=3.4 / Flutter >=3.22.
- FRB exactly 2.8.0.
- Native identity `rust_lib_dxtr_box`.
- Exactly three native profiles.
- `dxtr_box/1` remains readable.
- Primary data authoritative over indexes.
- `get` and `containsKey` remain authoritative native reads.
- No Dart whole-box cache.
- Full encrypted authentication.
- Query/index/migration correctness.
- Native-size regression policy.
- Five-platform staged consumer builds.
- Change-aware CI never weakens the final merge quality bar.
- Dart 3.13 recorded-use/native tree shaking remains deferred.

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
make benchmark-read-path
make native-size-regression
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

See `docs/PERFORMANCE_READ_PATH_05.md` for the normative 0.5 evidence record and `docs/PROJECT_HANDOFF.md` for current execution state.