# dxtr_box 0.5 Performance / Read-path Optimization

## Status

0.5 is active. PR 1 is the measurement-only read-path decomposition phase and has a corrected artifact-producing baseline from GitHub Actions after aligning the Rust benchmark payload with the public `DxtrCodec` wire shape.

PR 1 changes no production read semantics, storage format, encryption behavior, public `Box` API, or native capability profile.

This document uses four evidence classes:

- **Measured fact** — directly observed by a named harness/run.
- **Inference** — interpretation supported by measurements but not directly isolated by one timer.
- **Implemented optimization** — production behavior changed with controlled before/after evidence.
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

`Box.get` and `Box.containsKey` remain authoritative native reads. Do not introduce a Dart whole-box cache to make point reads appear faster. Encryption authentication, cross-process visibility, durability, query/index/migration behavior, and storage compatibility remain correctness gates.

Dart 3.13 recorded-use/native tree shaking remains explicitly outside this milestone unless requested separately.

## Previous measured fact — 0.3 diagnosis

The 0.3 shared-runner diagnostic observed approximately:

```text
native plaintext get hit       225.726 us/op
Dart MessagePack decode only     6.018 us/op
native containsKey hit         193.830 us/op
Dart metadata membership         6.532 us/op
```

Those values are diagnostic rather than performance guarantees. The 0.3 harness could not decompose the native region; it included FRB call/response, redb read setup and lookup, native MessagePack validation, payload copying, and decrypt/authenticate where applicable.

See `docs/POINT_READ_DIAGNOSIS_03.md`.

## PR 1 — decomposition harness

### Rust in-process harness

`rust/src/read_path_bench.rs` is a `#[cfg(test)]` module and its benchmark is ignored during ordinary test execution. `make benchmark-read-path` invokes it explicitly in release mode.

It measures:

1. `redb_read_transaction_create`
2. `redb_read_transaction_open_table`
3. `redb_point_lookup_borrowed` hit/miss on one stable snapshot
4. `redb_point_lookup_copy`
5. `messagepack_validate`
6. `vec_payload_copy`
7. `decrypt_authenticate`
8. full production `db_get` plaintext/encrypted hit/miss
9. full production `db_contains_key` hit/miss

### Public-wire payload rule

The Rust payload generator must represent the same logical wire shape produced by `DxtrCodec.encode` for the Dart benchmark workload. In particular, the map is encoded using the `@dxtr:map` tagged representation and the body is a MessagePack string, not a `Vec<u8>` serialized as thousands of sequence elements.

This rule was added after review identified that the original run #7 Rust medium payload was structurally different from the public Dart payload. Therefore run #7's 17.369 us medium `messagepack_validate` value is superseded and must not be used for optimization decisions.

### Dart / FRB harness

`test/read_path_benchmark_test.dart` measures:

- `dart_dxtr_codec_decode`
- `native_adapter_get` through `FrbNativeDxtrApi`
- public `Box.get`
- `native_adapter_contains_key`
- public `Box.containsKey`

It covers small/medium payloads, plaintext/encrypted where relevant, and hit/miss cases where relevant. Assertions are performed outside timed loops.

### Local command

```bash
make benchmark-read-path
```

Default local configuration:

```text
Rust iterations: 2000
Dart iterations: 1000
samples:          7
```

CI baseline configuration:

```text
Rust iterations: 1000
Dart iterations: 500
samples:          5
```

## Machine-readable evidence

The benchmark must produce both:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

The Makefile uses an absolute repository-root output path for the Rust test because Cargo executes the unit-test process with the crate directory as its current working directory. The target fails closed if either JSONL file is missing.

The dedicated `Read-path Benchmark` workflow also captures:

```text
flutter-version.txt
rust-version.txt
cargo-version.txt
runner.txt
cpu.txt
```

and uploads all evidence as `read-path-benchmark-linux-x64`. Missing artifact files are treated as an error.

## Corrected PR 1 baseline — GitHub Actions run #11

Successful workflow:

```text
Read-path Benchmark #11
run id: 31949461503
artifact: read-path-benchmark-linux-x64
artifact id: 9264234449
head: 09c407139b824c3cbb6ce12f3bd8dacf84d03285
```

Runner/toolchain:

```text
OS:       Ubuntu hosted runner, Linux x86_64, kernel 6.17.0-1022-azure
CPU:      Intel Xeon Platinum 8370C @ 2.80GHz, 4 logical CPUs
Flutter:  3.47.0 stable
Dart:     3.13.0 stable
rustc:    1.97.1
cargo:    1.97.1
```

Shared-runner timings remain diagnostic. They are not release-performance guarantees.

## Measured fact — Rust decomposition, corrected public-wire payload

Median times from run #11:

| Operation | Small | Medium |
|---|---:|---:|
| redb read transaction create | 0.199 us | 0.200 us |
| redb transaction + table open | 0.492 us | 0.567 us |
| borrowed point lookup hit | 0.100 us | 0.116 us |
| borrowed point lookup miss | 0.087 us | 0.106 us |
| point lookup + copy hit | 0.107 us | 0.191 us |
| MessagePack validation | 0.084 us | 0.211 us |
| standalone Vec copy | 0.035 us | 0.112 us |
| full `db_get` plaintext hit | 0.742 us | 1.055 us |
| full `db_get` plaintext miss | 0.599 us | 0.664 us |
| full `db_contains_key` hit | 0.591 us | 0.655 us |
| full `db_contains_key` miss | 0.583 us | 0.651 us |
| decrypt/authenticate | 1.700 us | 4.952 us |
| full `db_get` encrypted hit | 2.454 us | 6.056 us |
| full `db_get` encrypted miss | 0.596 us | 0.661 us |

### Direct observations

For this corrected run:

- redb transaction creation itself is sub-microsecond.
- transaction plus table open is ~0.57 us for the medium workload and is the largest directly isolated plaintext-native subcomponent measured here.
- raw borrowed point lookup remains small (~0.12 us medium).
- lookup plus payload copy is ~0.19 us medium.
- MessagePack validation is ~0.21 us medium and is **not** the dominant successful-read cost after the public-wire correction.
- full in-process plaintext `db_get` is ~1.06 us medium.
- encrypted hit cost is dominated by mandatory authenticated decryption (~4.95 us medium), producing ~6.06 us full encrypted `db_get`.
- misses and `containsKey` remain around ~0.65 us in-process because they avoid successful-payload decode/validation work.

The original run #7 conclusion that MessagePack validation dominated the medium native read was caused by a benchmark payload-shape mismatch and is superseded by run #11.

## Measured fact — Dart / public path, run #11

Median times from run #11:

| Operation | Small | Medium |
|---|---:|---:|
| Dart `DxtrCodec.decode` | 10.368 us | 5.972 us |
| native-adapter get plaintext hit | 132.822 us | 90.470 us |
| native-adapter get plaintext miss | 91.612 us | 74.644 us |
| public `Box.get` plaintext hit | 102.628 us | 102.118 us |
| public `Box.get` plaintext miss | 90.136 us | 87.188 us |
| native-adapter get encrypted hit | 90.408 us | 94.312 us |
| public `Box.get` encrypted hit | 91.286 us | 109.880 us |
| native-adapter `containsKey` hit | 78.396 us | 74.310 us |
| public `Box.containsKey` hit | 76.318 us | 74.672 us |

The ordering of some Dart/native-adapter/public medians is non-monotonic on the shared runner. Therefore these rows are useful as end-to-end diagnostic baselines but must not be treated as additive component timings.

## Inference — cross-runtime / FRB / async boundary

PR 1 intentionally does not add a benchmark-only FRB echo/passthrough method to the shipped API.

The corrected run makes the structural gap much clearer: in-process medium plaintext `db_get` is ~1.06 us while the Dart native-adapter path is ~90.47 us and public `Box.get` is ~102.12 us. Likewise, in-process `containsKey` is ~0.65 us while the Dart adapter/public path is ~74 us.

This strongly indicates that the cross-runtime/native-adapter/async region is the dominant end-to-end area to investigate. However, the difference is **not a direct FRB timer**. It also contains Dart async scheduling, generated binding behavior, allocation/conversion, and cross-harness/runtime effects.

Do not subtract Rust and Dart medians and publish the result as an exact FRB overhead percentage.

## Phase A conclusion

Phase A now has a corrected evidence baseline sufficient to choose the next investigation order.

### Highest-priority end-to-end investigation

The cross-runtime / generated-FRB / Dart async adapter region.

Corrected medium plaintext evidence:

```text
in-process Rust db_get             1.055 us
Dart native-adapter get           90.470 us
public Box.get                    102.118 us
Dart DxtrCodec.decode               5.972 us
```

Because the current harness does not isolate FRB from Dart async scheduling and conversion, PR 2 must first add a controlled boundary diagnostic before making a bridge-specific production change.

### Native single-key targets

Native transaction/table-open, validation, and copy costs are all sub-microsecond for plaintext public-wire payloads in this workload. They may still contain avoidable work, but none explains the ~90–100 us public-path latency.

For encrypted reads, authenticated decryption is a real native cost and must not be weakened.

### Lower-priority / deferred ordinary-read target

Long-lived default read transactions/read sessions. Per-call transaction/table-open cost is measurable, but the corrected evidence does not justify taking on stale-snapshot semantics as the first optimization.

## Implemented optimization

None in PR 1. This remains intentional: PR 1 establishes measurement infrastructure and corrected evidence only.

## Deferred / rejected shortcuts

Do not implement as Phase B shortcuts:

- long-lived default read transactions with implicit stale snapshots;
- Dart metadata-backed authoritative `containsKey`;
- Dart whole-box caching;
- skipped encrypted authentication;
- skipped native validation without a separate correctness argument;
- storage-format changes solely for benchmark numbers;
- speculative FRB buffer rewrites without boundary evidence;
- public multi-key API solely for benchmark convenience.

## PR 2 decision gate

PR 2 should:

1. preserve the corrected public-wire benchmark shape;
2. add a controlled diagnostic for the generated-FRB / Dart async boundary without leaving benchmark-only production API surface behind;
3. inspect generated FRB call mode, async scheduling, request/response conversion, and payload allocation/copy behavior;
4. select a production single-key optimization only after the boundary diagnostic identifies an actionable cost;
5. keep native copy/validation cleanup as secondary work unless controlled evidence shows it matters end-to-end;
6. preserve authoritative native reads, cross-process visibility, and full encryption authentication;
7. avoid implicit stale read sessions;
8. record before/after numbers on the same methodology/environment where practical;
9. keep all correctness, migration, encryption, profile, native-size, FRB-drift, minimum-SDK, and five-platform gates green.

## Planned 0.5 sequence

```text
PR 1 — read-path benchmark decomposition                         corrected evidence baseline
PR 2 — single-key read optimization backed by boundary evidence next
PR 3 — product-grade batch/multi-key read path
PR 4 — read-session investigation; implement only if freshness semantics remain explicit/safe
PR 5 — expanded comparison matrix + 0.5 closure audit
```

PR 3 should benchmark 10 / 100 / 1,000-key reads and avoid N FRB crossings plus N independent read transactions where a one-snapshot batch design is correct.

PR 4 must document redb snapshot lifetime, writer interaction, stale-data semantics, resource retention, Flutter lifecycle, multi-handle behavior, and cross-process expectations even if the conclusion is "do not implement".

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

Do not compare unrelated shared runners as controlled A/B evidence. Prefer same-environment/same-methodology before/after runs.

Correctness, durability, encryption authentication, cross-process visibility, storage compatibility, minimum SDK support, native-size policy, and five-platform consumer builds remain harder requirements than benchmark speed.
