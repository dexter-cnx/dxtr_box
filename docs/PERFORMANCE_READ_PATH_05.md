# dxtr_box 0.5 Performance / Read-path Optimization

## Status

0.5 is active. PR 1 is the measurement-only read-path decomposition phase and now has a successful artifact-producing baseline from GitHub Actions.

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

## PR 1 baseline — GitHub Actions run #7

Successful workflow:

```text
Read-path Benchmark #7
run id: 31947858383
artifact: read-path-benchmark-linux-x64
artifact id: 9263812713
head: ec0da61bdd53f70201a31f3c44fddfdfe325a3c8
```

Runner/toolchain:

```text
OS:       Ubuntu 24.04 hosted runner, Linux x86_64
CPU:      AMD EPYC 9V74, 4 logical CPUs
Flutter:  3.47.0 stable
Dart:     3.13.0 stable
rustc:    1.97.1
cargo:    1.97.1
```

Shared-runner timings remain diagnostic. They are not release-performance guarantees.

## Measured fact — Rust decomposition

Median times from run #7:

| Operation | Small | Medium |
|---|---:|---:|
| redb read transaction create | 0.112 us | 0.113 us |
| redb transaction + table open | 0.395 us | 0.387 us |
| borrowed point lookup hit | 0.040 us | 0.106 us |
| borrowed point lookup miss | 0.030 us | 0.098 us |
| point lookup + copy hit | 0.059 us | 1.650 us |
| MessagePack validation | 0.314 us | 17.369 us |
| standalone Vec copy | 0.017 us | 0.108 us |
| full `db_get` plaintext hit | 0.875 us | 19.633 us |
| full `db_get` plaintext miss | 0.494 us | 0.545 us |
| full `db_contains_key` hit | 0.498 us | 0.554 us |
| full `db_contains_key` miss | 0.487 us | 0.545 us |
| decrypt/authenticate | 2.273 us | 5.878 us |
| full `db_get` encrypted hit | 3.176 us | 24.204 us |
| full `db_get` encrypted miss | 0.498 us | 0.558 us |

### Direct observations

For this run:

- redb transaction creation itself is sub-microsecond and is not the dominant successful-read cost.
- redb table open plus transaction setup remains sub-microsecond.
- raw borrowed point lookup is tiny relative to the full medium successful read.
- copying the redb value becomes visible for the medium payload (~1.65 us) but remains much smaller than native MessagePack validation.
- native MessagePack validation is the dominant directly isolated component for the medium plaintext hit (~17.37 us versus ~19.63 us full `db_get`).
- encrypted hit cost adds measurable authenticated-decryption work (~2.27 us small, ~5.88 us medium), and authentication must not be weakened.
- misses and `containsKey` do not pay payload validation/decode cost and stay near the transaction/table-open region in the in-process Rust harness.

These observations identify transaction reuse as a lower-priority Phase B target than successful-hit validation/copy work for this workload.

## Measured fact — Dart / public-path baseline

Median times from run #7:

| Operation | Small | Medium |
|---|---:|---:|
| Dart `DxtrCodec.decode` | 8.868 us | 5.908 us |
| native-adapter get plaintext hit | 133.990 us | 90.866 us |
| native-adapter get plaintext miss | 98.074 us | 73.596 us |
| public `Box.get` plaintext hit | 98.852 us | 107.654 us |
| public `Box.get` plaintext miss | 88.612 us | 81.518 us |
| native-adapter get encrypted hit | 92.412 us | 96.178 us |
| public `Box.get` encrypted hit | 93.544 us | 111.640 us |
| native-adapter `containsKey` hit | 76.946 us | 74.524 us |
| public `Box.containsKey` hit | 75.272 us | 81.616 us |

The ordering of some Dart/native-adapter/public medians is non-monotonic on the shared runner (for example a public measurement can be lower than its adjacent adapter measurement). Therefore these rows are useful as end-to-end diagnostic baselines but must not be treated as additive component timings.

## Inference — FRB / async boundary

PR 1 intentionally does not add a benchmark-only FRB echo/passthrough method to the shipped API.

The large gap between in-process Rust `db_*` timings and Dart native-adapter/public timings indicates that the cross-runtime/native-adapter region is material in the end-to-end path. However, the difference is **not a direct FRB timer**. It also contains Dart async scheduling, generated binding behavior, allocation/conversion, and cross-harness/runtime effects.

Do not subtract the Rust and Dart medians and publish the result as an exact FRB overhead percentage.

If Phase B needs to optimize this region, first add a controlled measurement that does not leave benchmark-only plumbing in the production API.

## Phase A conclusion

Phase A is complete enough to select the next investigation order.

### Highest-priority measured native target

Successful-hit native MessagePack validation, especially as payload size grows.

The medium-payload run measured:

```text
MessagePack validation          17.369 us
full plaintext db_get           19.633 us
redb lookup + copy               1.650 us
transaction + table open         0.387 us
```

This does **not** authorize simply removing validation. PR 2 must first establish the correctness reason for validation on reads and determine whether validation can be made cheaper, deduplicated safely, or moved/restructured without weakening corruption detection, storage compatibility, encryption authentication, or public codec behavior.

### Secondary measured native target

Avoidable payload allocations/copies on successful medium reads.

### Material inferred end-to-end target

FRB/native-adapter/async boundary overhead. This is material by comparison but not yet isolated precisely enough to justify a specific bridge optimization.

### Lower-priority target for ordinary single-key reads

Per-call redb transaction creation/table open. It is measurable but too small in this baseline to justify stale long-lived snapshots as the first optimization.

## Implemented optimization

None in PR 1. This remains intentional: PR 1 establishes measurement infrastructure and evidence only.

## Deferred / rejected shortcuts

Do not implement as Phase B shortcuts:

- long-lived default read transactions with implicit stale snapshots;
- Dart metadata-backed authoritative `containsKey`;
- Dart whole-box caching;
- skipped encrypted authentication;
- storage-format changes solely for benchmark numbers;
- speculative FRB buffer rewrites without boundary evidence;
- public multi-key API solely for benchmark convenience.

Native MessagePack validation may be changed only with a documented correctness argument and before/after evidence; “it is expensive” alone is not sufficient reason to remove it.

## PR 2 decision gate

PR 2 should:

1. preserve the PR 1 harness unchanged enough to provide a comparable before/after baseline;
2. investigate why successful reads revalidate MessagePack and whether validation work is duplicated relative to write-time guarantees / encrypted authentication / durable-file corruption handling;
3. inspect the successful-hit copy path for avoidable `Vec` allocations/copies;
4. avoid read-session/stale-snapshot work unless new evidence overturns the current priority;
5. if bridge overhead becomes the intended target, add a controlled boundary diagnostic first rather than guessing;
6. record before/after numbers on the same methodology/environment where practical;
7. keep all correctness, migration, encryption, profile, native-size, FRB-drift, and five-platform gates green.

## Planned 0.5 sequence

```text
PR 1 — read-path benchmark decomposition                         complete evidence baseline
PR 2 — single-key read optimization backed by PR 1 evidence     next
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
