# dxtr_box Code Walkthrough

This walkthrough describes the publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, completed 0.4 hardening, change-aware CI, and 0.5 read-path work through PR3.

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
  -> native capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lightweight metadata, lifecycle guards, query objects, and Hive CE migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance, and plaintext-to-encrypted migration.

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

`Box.containsKey` follows the same authoritative native path and Rust `contains_key` also uses `#[frb(sync)]`.

Only these tiny single-key read entrypoints use synchronous FRB dispatch. Query, batch reads, scans, mutations, and migrations remain asynchronous.

PR2 controlled evidence:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

No Dart whole-box cache, metadata-backed authoritative shortcut, or long-lived stale read snapshot was introduced.

## 6. Production batch-read path after PR #36

Public API:

```dart
Future<List<MapEntry<String, dynamic>>> getAll(Iterable<String> keys)
```

Execution:

```text
Box.getAll
  -> validate all requested keys
  -> NativeBatchReadApi.getAll
  -> FrbNativeDxtrApi.getAll
  -> generated asynchronous FRB getAll
  -> Rust api::get_all
  -> db::get_all
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative key lookups
  -> decrypt/authenticate every encrypted hit
  -> validate MessagePack every hit
  -> one Vec<NativeBatchRecord> response
  -> Dart DxtrCodec.decode per hit
```

Semantics:

```text
input order for hits: preserved
missing keys:         omitted
duplicate input keys: duplicate result entries
empty input:          empty result without native crossing
```

The batch entrypoint intentionally stays asynchronous. A 1,000-key batch must not inherit the single-key `#[frb(sync)]` policy and synchronously occupy the Dart/UI isolate.

`NativeBatchReadApi` is a separate capability seam so the core `NativeDxtrApi` contract is not widened for unrelated injected adapters.

## 7. PR3 benchmark evidence

`test/batch_read_benchmark_test.dart` compares `Box.getAll` with N independent `Box.get` calls using the same populated box.

Read-path Benchmark #31, run `31978434993`:

| Keys | `getAll` | Independent `get` | Relative improvement |
|---:|---:|---:|---:|
| 10 | 445 us | 636 us | ~1.43x |
| 100 | 814 us | 5,256 us | ~6.46x |
| 1,000 | 3,729 us | 32,032 us | ~8.59x |

These hosted-runner medians are diagnostic. The important architectural result is that increasing key count no longer requires one Dart/FRB crossing and one redb transaction/table open per key.

Native integration additionally verifies encrypted batch reads while preserving order, duplicate behavior, and missing-key behavior.

## 8. Existing decomposed read-path harness

`rust/src/read_path_bench.rs` measures transaction creation, table open, point lookup/copy, MessagePack validation, payload copy, authenticated decryption, `db_get`, and `db_contains_key`.

`test/read_path_benchmark_test.dart` measures codec decode plus adapter/public point-read paths. `test/read_path_boundary_benchmark_test.dart` isolates generated FRB dispatch from the Future-based adapter.

Machine-readable evidence from the dedicated read-path workflow remains:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
build/read-path/dart-boundary.jsonl
```

The permanent workflow is read-only and uploads evidence/toolchain metadata; temporary PR3 source-generation logic is not retained.

## 9. Query execution

`Box.query(BoxQuery)` remains one structured query through one asynchronous FRB call:

```text
Box.query
  -> serialize query AST
  -> one FRB call
  -> one redb ReadTransaction snapshot
  -> optional index candidate narrowing
  -> authoritative primary reads
  -> optional decrypt/authenticate
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

Persisted indexes narrow candidates only; they do not replace predicate re-evaluation and do not satisfy ORDER BY.

## 10. Encryption/profile safety

Encrypted point and batch reads preserve full AEAD authentication. Encrypted boxes can use native scan queries but cannot create persisted plaintext-derived secondary indexes.

Profiles remain exactly:

```text
minimal
encryption
full
```

Reduced profiles reject indexed boxes they cannot safely maintain.

## 11. Hive CE migration

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

## 12. FRB drift and package gates

Checked-in bindings are generated with FRB 2.8.0. Full CI regenerates them and fails on any diff.

Package readiness remains:

```text
make package-readiness
  -> dart doc
  -> dart pub publish --dry-run --ignore-warnings
```

## 13. Native-size policy

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
```

Minimal, encryption, and full are measured independently.

## 14. Staged published consumers

`tool/validate_published_consumer.dart` validates the consumer-visible package payload on Android, iOS, macOS, Linux, and Windows.

## 15. Change-aware CI

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

Full validation remains mandatory before merge.

## 16. 0.5 implementation sequence

```text
PR 1 / #33 — read-path decomposition + corrected baseline      complete
PR 2 / #35 — sync FRB single-key reads                         complete / merged
PR 3 / #36 — one-snapshot batch/multi-key reads                complete / final validation
PR 4       — read-session investigation                        next
PR 5       — expanded comparison + 0.5 closure audit          planned
```

PR4 should evaluate whether explicit reusable read sessions provide enough benefit after `getAll` to justify stale-snapshot/resource/lifecycle complexity. Ordinary `get` must not silently move to a long-lived snapshot.

## 17. Invariants to preserve

- Dart >=3.4 / Flutter >=3.22.
- FRB exactly 2.8.0.
- Native identity `rust_lib_dxtr_box`.
- Exactly three native profiles.
- `dxtr_box/1` remains readable.
- Primary data authoritative over indexes.
- `get`, `containsKey`, and `getAll` remain authoritative native reads.
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
make benchmark-batch-read
make native-size-regression
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

See `docs/PERFORMANCE_READ_PATH_05.md` for the normative 0.5 evidence record and `docs/PROJECT_HANDOFF.md` for current execution state.
