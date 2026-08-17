# dxtr_box 0.5 Performance / Read-path Optimization

## Status

0.5 is active.

```text
PR 1 / #33 — read-path decomposition + corrected baseline      complete / merged
PR 2 / #35 — single-key FRB boundary optimization              complete / merged
PR 3 / #36 — one-snapshot batch/multi-key read path            complete / merged
PR 4 / #37 — read-session investigation                        decision complete / validation
PR 5       — comparison matrix + 0.5 closure audit             next
```

This document distinguishes measured fact, inference, implemented optimization, and rejected/deferred ideas. Hosted-runner timings are diagnostic, not release-performance guarantees.

## Stable constraints

Preserve throughout 0.5:

```text
Dart >= 3.4
Flutter >= 3.22
native library = rust_lib_dxtr_box
native profiles = minimal | encryption | full
format_version = dxtr_box/1
flutter_rust_bridge = 2.8.0
redb = 2.1.0
```

`Box.get`, `Box.containsKey`, and `Box.getAll` remain authoritative native reads. Do not introduce a Dart whole-box cache or implicit long-lived stale snapshot. Preserve encryption authentication, cross-process visibility, durability, query/index/migration behavior, and storage compatibility.

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

`test/read_path_boundary_benchmark_test.dart` separates generated FRB calls from the Future-based Dart adapter.

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

PR #36 added:

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

Read-path Benchmark #31, run `31978434993`:

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

PR3 accepted efficient multi-key support because it is useful independently of benchmarking and amortizes both Dart/FRB crossing and redb setup while preserving storage/encryption semantics.

PR #36 merged as `392bdf6e0af3741133eb4fb28b0638f4ecbd5a32` after the full quality bar passed.

## Remaining cost after PR3

For point reads, public Future/adapter work remains more expensive than direct generated sync FRB calls. Do not make the public API synchronous merely to chase microbenchmarks.

For known multi-key workloads, PR3 now amortizes boundary and transaction setup cost. That substantially reduces the motivation for cross-call snapshot reuse.

Encrypted hits still carry mandatory authenticated-decryption cost and must not weaken authentication for performance.

## PR4 — reusable read-session investigation

Detailed record: `docs/READ_SESSION_INVESTIGATION_05.md`.

### redb semantics

A redb `ReadTransaction` captures the database snapshot at `begin_read()`. Data committed later is not visible through that transaction. Read transactions may coexist with writes.

Therefore a reusable session has unavoidable semantics:

```text
session opens at T0
writer commits at T1
session reads again at T2
=> T2 read still sees the T0 snapshot
```

That is coherent snapshot behavior, but it is intentionally stale relative to post-T0 commits. It cannot transparently replace ordinary `get`, `containsKey`, or `getAll` without weakening their established fresh-per-call behavior.

### incremental performance case

The representative PR1 native cost that a reusable transaction could avoid was approximately:

```text
transaction + table open   0.567 us
```

After PR2, generated FRB point reads are already low-single-digit microseconds, while the Future-based adapter path remains higher. A session spanning multiple Dart calls would still pay repeated Dart/FRB call overhead unless it changes the API shape to batch work.

For known batches, PR3 already uses the optimal shape available to the current API contract: one public call, one FRB call, one redb snapshot, N reads.

**Inference:** snapshot reuse across separate calls has little demonstrated performance value unless the caller specifically needs coherent multi-call snapshot semantics. No such product requirement exists in the current milestone.

### lifecycle/resource case

A production session API would add explicit semantics for:

- session close/dispose and leaks;
- box close while sessions exist;
- compact while sessions exist;
- plaintext-to-encrypted migration while sessions exist;
- multiple Dart handles and isolates;
- native session identity/registry ownership;
- stale session IDs after teardown;
- encrypted value authentication on every session read.

This is meaningful lifecycle/API surface, not a transparent optimization.

### pinned redb 2.1.0 consideration

The project intentionally remains pinned to redb 2.1.0. The upstream redb 2.1.1 changelog specifically lists a fix for a panic when `compact()` is called while a read transaction is in progress.

That known version-adjacent maintenance interaction is additional evidence against deliberately introducing long-lived read transactions while staying on 2.1.0. PR4 does **not** upgrade redb; dependency upgrades remain an independent compatibility/regression decision.

### PR4 decision

**Rejected for 0.5:** production reusable read-session API.

No public API, FRB binding, native profile, dependency, or storage-format change is introduced.

Reconsider only if a future consumer has a concrete need for one coherent snapshot across multiple logically separate operations and accepts an explicitly documented stale-within-session contract. Any reconsideration must bring new workload benchmarks plus close/leak/compact/migration lifecycle tests.

## Deferred/rejected shortcuts

Do not use:

- Dart whole-box caching;
- metadata-backed authoritative `containsKey`;
- skipped encrypted authentication;
- skipped native validation without a correctness case;
- storage-format changes solely for benchmark numbers;
- long-lived implicit stale read snapshots;
- hidden periodically refreshed snapshots;
- public synchronous API changes solely for microbenchmark results.

## Next — PR5 closure audit

PR5 should rerun the comparison matrix with the final 0.5 APIs where appropriate, verify all hard compatibility/correctness gates, and decide whether 0.5 can close.

The read-session decision should remain closed unless new evidence materially changes PR4's conclusion.

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
