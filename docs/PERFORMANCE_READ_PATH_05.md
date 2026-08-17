# dxtr_box 0.5 Performance / Read-path Optimization

## Status

0.5 is active.

```text
PR 1 / #33 — read-path decomposition + corrected baseline      complete
PR 2 / #35 — single-key FRB boundary optimization              complete / merged
PR 3 / #36 — one-snapshot batch/multi-key read path            complete / final validation
PR 4       — read-session investigation                        next
PR 5       — comparison matrix + 0.5 closure audit             planned
```

This document distinguishes measured fact, inference, implemented optimization, and deferred ideas. Hosted-runner timings are diagnostic, not release-performance guarantees.

## Stable constraints

Preserve throughout 0.5:

```text
Dart >= 3.4
Flutter >= 3.22
native library = rust_lib_dxtr_box
native profiles = minimal | encryption | full
format_version = dxtr_box/1
flutter_rust_bridge = 2.8.0
```

`Box.get`, `Box.containsKey`, and `Box.getAll` remain authoritative native reads. Do not introduce a Dart whole-box cache. Preserve encryption authentication, cross-process visibility, durability, query/index/migration behavior, and storage compatibility.

Dart 3.13 recorded-use/native tree shaking remains outside this milestone unless explicitly requested.

## Benchmark harnesses

### Rust in-process decomposition

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

The Rust payload represents the same logical tagged-map wire shape produced by public `DxtrCodec.encode`.

### Dart/public read-path benchmark

`test/read_path_benchmark_test.dart` measures codec decode, native-adapter point reads, and public `Box.get` / `Box.containsKey` paths.

### PR2 boundary benchmark

`test/read_path_boundary_benchmark_test.dart` separates generated FRB calls from the Future-based Dart adapter and uses existing sync FRB behavior as a control.

### PR3 batch benchmark

`test/batch_read_benchmark_test.dart` compares one `Box.getAll` batch with N independent `Box.get` calls at 10, 100, and 1,000 keys.

## PR1 corrected baseline — run #11

Read-path Benchmark #11, run `31949461503`, established representative corrected medium medians:

```text
Rust in-process
  transaction + table open       0.567 us
  lookup + copy hit              0.191 us
  MessagePack validation         0.211 us
  full plaintext db_get hit      1.055 us
  full db_contains_key hit       0.655 us
  decrypt/authenticate           4.952 us
  full encrypted db_get hit      6.056 us

Dart/public
  native adapter get hit        90.470 us
  public Box.get hit           102.118 us
  DxtrCodec.decode               5.972 us
  native adapter contains hit   74.310 us
  public Box.containsKey hit    74.672 us
```

**Measured fact:** native transaction/lookup/copy/validation work was small relative to the Dart/native-adapter path.

**Inference:** the cross-runtime/generated-binding/Dart-async region was the highest-priority target.

## PR2 — single-key FRB boundary optimization

Controlled pre-change evidence:

```text
generated FRB get via NormalTask             ~226 us/op
generated FRB containsKey via NormalTask     ~197 us/op
native db_get plaintext hit                  ~0.66 us/op
native db_contains_key hit                   ~0.48 us/op
```

Production change in PR #35:

```rust
#[frb(sync)]
pub fn get(...)

#[frb(sync)]
pub fn contains_key(...)
```

Only these tiny point-read entrypoints changed call mode. Public Dart contracts remain Future-based. Query, batch reads, scans, mutations, migrations, and other heavier work remain asynchronous.

Read-path Benchmark #24, run `31954326856`:

| Operation | Median |
|---|---:|
| generated FRB get sync hit | 4.312 us |
| generated FRB get sync miss | 1.888 us |
| generated FRB containsKey sync hit | 2.570 us |
| generated FRB containsKey sync miss | 1.734 us |
| native adapter get async hit | 21.076 us |
| native adapter containsKey async hit | 17.636 us |

Relative to controlled pre-change boundary evidence:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

PR2 demonstrated that the dominant point-read overhead was FRB `NormalTask` dispatch rather than redb.

## PR3 — one-snapshot batch reads

### Product contract

PR #36 introduces:

```dart
Future<List<MapEntry<String, dynamic>>> Box.getAll(
  Iterable<String> keys,
)
```

Architecture:

```text
N keys
  -> one public batch call
  -> one asynchronous FRB call
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative lookups
  -> optional decrypt/authenticate per hit
  -> MessagePack validation per hit
  -> one response
```

Semantics:

- hits preserve input order;
- missing keys are omitted;
- duplicate input keys produce duplicate result entries;
- empty input returns empty without a native crossing;
- all keys are validated before crossing native;
- encrypted hits retain full AEAD authentication;
- no cache or long-lived snapshot is introduced.

The FRB batch entrypoint intentionally remains asynchronous. The single-key sync optimization must not be generalized to potentially large batches.

### PR3 validation run

Read-path Benchmark #31:

```text
run id: 31978434993
implementation commit: dc457be39c8055ea09b76dc7de47f377315875dc
Flutter: 3.47.0 stable
Dart: 3.13.0
Rust: 1.97.1
runner: hosted Linux x64
```

The run generated checked-in FRB 2.8.0 bindings, then passed:

- `make ci-fast`;
- Flutter analyze with no issues;
- Dart fast tests and public/storage contract guard;
- rustfmt + clippy;
- minimal/encryption/full compile checks;
- cheap Rust tests;
- `make native-test`;
- encrypted `getAll` native integration semantics;
- `make benchmark-batch-read`.

### PR3 batch evidence

Median hosted-runner timings:

| Keys | `Box.getAll` | N independent `Box.get` | Relative improvement |
|---:|---:|---:|---:|
| 10 | 445 us | 636 us | ~1.43x |
| 100 | 814 us | 5,256 us | ~6.46x |
| 1,000 | 3,729 us | 32,032 us | ~8.59x |

Approximate latency reduction:

```text
10 keys      ~30%
100 keys     ~85%
1,000 keys   ~88%
```

The larger improvement at 100/1,000 keys is consistent with amortizing Dart/FRB crossings and redb transaction/table-open overhead across the batch. This is an inference from the architecture plus measured result; it is not a claim that every workload will realize the same ratio.

### PR3 decision

**Accepted:** efficient multi-key support is justified and implemented.

The product API is useful independently of benchmarking and preserves authoritative storage/encryption semantics. It is preferable to requiring callers to issue N independent point reads when they already know the key set.

Temporary source-generation workflow/script used during PR construction are removed before merge. Permanent benchmark CI remains read-only.

## Remaining cost after PR3

For point reads, public Future/adapter work remains more expensive than direct generated sync FRB calls. Do not make the public API synchronous merely to chase microbenchmarks.

For known multi-key workloads, PR3 now amortizes the boundary and transaction setup cost. That reduces the motivation for implicit long-lived read snapshots.

Encrypted hits still carry mandatory authenticated-decryption cost and must not weaken authentication for performance.

## Deferred/rejected shortcuts

Do not use:

- Dart whole-box caching;
- metadata-backed authoritative `containsKey`;
- skipped encrypted authentication;
- skipped native validation without a correctness case;
- storage-format changes solely for benchmark numbers;
- long-lived implicit stale read snapshots;
- public synchronous API changes solely for microbenchmark results.

## Next — PR4 read-session investigation

PR4 must evaluate rather than assume a reusable read-session API is beneficial.

Investigate:

1. redb snapshot/transaction lifetime;
2. writer interaction and blocking behavior;
3. stale-data semantics;
4. resource retention;
5. Flutter lifecycle/disposal;
6. multi-handle behavior;
7. cross-process freshness;
8. incremental benefit after `Box.getAll`.

Do not silently change ordinary `get` to use a long-lived stale snapshot. If an explicit session cannot demonstrate a meaningful use case/performance win without unacceptable semantics or complexity, document the rejection and move to PR5.

## PR5 closure audit

PR5 should re-run the comparison matrix with the final 0.5 APIs where appropriate, verify all hard compatibility/correctness gates, and decide whether 0.5 can close.

## Performance evidence policy

Every production performance change must record:

```text
before
after
delta
benchmark methodology
runner/toolchain metadata
correctness validation
```

Prefer controlled same-methodology comparisons. Correctness, durability, encryption authentication, cross-process visibility, storage compatibility, minimum SDK support, native-size policy, and five-platform consumer builds remain harder requirements than benchmark speed.
