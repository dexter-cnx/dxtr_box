# dxtr_box 0.5 Performance / Read-path Optimization

## Status

0.5 is active.

```text
PR 1 / #33 — read-path decomposition + corrected baseline      complete
PR 2 / #35 — single-key FRB boundary optimization             complete / ready to merge
PR 3       — batch/multi-key read path                        next
PR 4       — read-session investigation                       planned
PR 5       — comparison matrix + 0.5 closure audit            planned
```

This document distinguishes:

- **Measured fact** — directly observed by a named harness/run.
- **Inference** — interpretation supported by measurements.
- **Implemented optimization** — production behavior changed with before/after evidence.
- **Deferred idea** — intentionally not implemented in the current phase.

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

`Box.get` and `Box.containsKey` remain authoritative native reads. Do not introduce a Dart whole-box cache. Preserve encryption authentication, cross-process visibility, durability, query/index/migration behavior and storage compatibility.

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

The Rust payload must represent the same logical tagged-map wire shape produced by public `DxtrCodec.encode`. The earlier run #7 medium `Vec<u8>` payload mismatch is superseded and must not be used for bottleneck decisions.

### Dart/public read-path benchmark

`test/read_path_benchmark_test.dart` measures:

```text
dart_dxtr_codec_decode
native_adapter_get
public_box_get
native_adapter_contains_key
public_box_contains_key
```

### PR2 boundary benchmark

`test/read_path_boundary_benchmark_test.dart` separates generated FRB calls from the Future-based Dart adapter and uses existing sync FRB behavior as a control.

Machine-readable evidence:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
build/read-path/dart-boundary.jsonl
```

The dedicated workflow also records Flutter/Rust/Cargo/runner/CPU metadata and uploads `read-path-benchmark-linux-x64`.

## PR1 corrected baseline — run #11

Successful workflow:

```text
Read-path Benchmark #11
run id:      31949461503
artifact id: 9264234449
head:        09c407139b824c3cbb6ce12f3bd8dacf84d03285
```

Representative corrected medium medians:

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

### PR1 conclusion

**Measured fact:** corrected native transaction/lookup/copy/validation work is small relative to the Dart/native-adapter path. MessagePack validation is not the dominant plaintext read cost.

**Inference:** the cross-runtime/generated-binding/Dart-async region was the highest-priority target. PR1 intentionally did not change production behavior.

## PR2 boundary diagnosis

The controlled pre-change boundary run showed approximately:

```text
generated FRB get via NormalTask             ~226 us/op
generated FRB containsKey via NormalTask     ~197 us/op
native db_get plaintext hit                  ~0.66 us/op
native db_contains_key hit                   ~0.48 us/op
```

The Dart adapter added only a small amount on top of the generated async FRB call, so the dominant single-key cost was the generated FRB `NormalTask` dispatch path rather than redb or the adapter itself.

This was the decision gate for a production call-mode change.

## Implemented optimization — PR #35

Only the tiny production point-read Rust entrypoints now use synchronous FRB dispatch:

```rust
#[frb(sync)]
pub fn get(...)

#[frb(sync)]
pub fn contains_key(...)
```

Checked-in bindings were regenerated with `flutter_rust_bridge_codegen 2.8.0`.

Public Dart contracts remain Future-based through `NativeDxtrApi` / `FrbNativeDxtrApi`; this is not a public API break.

The following remain asynchronous and unchanged in call-mode policy:

```text
query
scan-style work
mutations
migration
other potentially heavier operations
```

No Dart cache or stale long-lived read transaction was introduced.

## PR2 post-change evidence — run #24

Successful workflow:

```text
Read-path Benchmark #24
run id: 31954326856
head:   b221386c9543b109d15be63ded63820356ca5ec4
```

Boundary medians:

| Operation | Median |
|---|---:|
| generated FRB get sync hit | 4.312 us |
| generated FRB get sync miss | 1.888 us |
| generated FRB containsKey sync hit | 2.570 us |
| generated FRB containsKey sync miss | 1.734 us |
| native adapter get async hit | 21.076 us |
| native adapter containsKey async hit | 17.636 us |

Relative to the controlled pre-change boundary evidence:

```text
generated FRB get        ~226 us -> 4.312 us   about 52x faster
generated FRB contains   ~197 us -> 2.570 us   about 77x faster
```

Hosted-runner timings remain diagnostic, not release-performance guarantees.

## PR2 public-path observations

The decomposed benchmark after the call-mode change recorded representative small plaintext medians:

```text
native-adapter get hit        32.744 us
public Box.get hit            28.422 us
native-adapter contains hit   17.936 us
public Box.containsKey hit    19.734 us
```

Medium plaintext medians included:

```text
native-adapter get hit        25.124 us
public Box.get hit            38.932 us
native-adapter contains hit   17.464 us
public Box.containsKey hit    20.136 us
```

Shared-runner ordering is noisy and these values are not additive component timings. The controlled direct generated-FRB comparison is the primary PR2 optimization evidence.

## Correctness validation

Full CI rerun `31954326887` passed `Merge Gate / full quality bar` with:

- Fast CI.
- Dart full tests.
- Rust minimal/encryption/full profiles.
- Rust cross-platform checks.
- Native integration.
- storage/migration/query regressions.
- FRB generated-binding drift check.
- package/docs + pub dry-run.
- minimum Flutter 3.22.0 / Dart 3.4.0 compatibility.
- native-size policy.
- benchmark correctness/diagnostic smoke.
- Android/iOS/macOS/Linux/Windows staged consumers.

Therefore PR2 satisfies the required performance-change evidence policy: before, after, methodology, toolchain context and correctness validation are all recorded.

## Remaining cost after PR2

After removing `NormalTask` dispatch from point reads, the Future-based Dart adapter remains materially more expensive than direct generated sync calls. This includes Dart async/Future scheduling and adapter/public-layer work.

Do **not** remove the public Future API in 0.5 merely to chase microbenchmarks. That would be a public API/behavior decision, not a bridge-internal optimization.

Native plaintext `db_get` remains around the microsecond level, so further single-key native micro-optimizations are lower priority than product-grade batching.

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

## Next — PR3 batch/multi-key reads

Target product shape:

```text
N keys
  -> one public/native batch API
  -> one FRB call
  -> one redb read transaction/snapshot
  -> N authoritative lookups
  -> optional decrypt/authenticate per hit
  -> one response
```

PR3 should:

1. define missing-key behavior;
2. define duplicate-key behavior;
3. preserve deterministic result ordering;
4. support encrypted boxes;
5. benchmark 10 / 100 / 1,000 keys;
6. compare against N independent `get` calls;
7. add Dart/Rust/native integration coverage;
8. avoid benchmark-only production API surface;
9. preserve storage/encryption/cross-process contracts.

## PR4 read-session investigation

Evaluate redb snapshot lifetime, writer interaction, stale-data semantics, resource retention, Flutter lifecycle, multi-handle behavior and cross-process expectations.

Do not silently change ordinary `get` to use a long-lived stale snapshot. If reusable sessions are justified, prefer explicit session semantics. Document the decision even if the result is “do not implement.”

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

Prefer controlled same-methodology comparisons. Do not publish exact FRB-overhead percentages by subtracting unrelated hosted-runner harnesses.

Correctness, durability, encryption authentication, cross-process visibility, storage compatibility, minimum SDK support, native-size policy and five-platform consumer builds remain harder requirements than benchmark speed.