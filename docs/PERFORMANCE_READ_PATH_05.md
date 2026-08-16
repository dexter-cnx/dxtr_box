# dxtr_box 0.5 Performance / Read-path Optimization

## Status

0.5 has started. PR 1 is measurement-only read-path decomposition. No production read semantics, storage format, encryption behavior, public Box API, or native capability profile is changed by this phase.

This document distinguishes four categories explicitly:

- **Measured fact** — directly observed by a named harness/run.
- **Inference** — interpretation supported by measurements but not directly timed as one isolated operation.
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
```

Do not introduce a Dart whole-box cache to make point reads appear faster. `Box.get` and `Box.containsKey` remain authoritative against native storage. Encryption authentication, cross-process visibility, durability, query/index/migration behavior, and storage compatibility remain correctness gates.

Dart 3.13 recorded-use/native tree shaking is explicitly outside this milestone unless requested separately.

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

## PR 1 — read-path benchmark decomposition

### Purpose

Measure the major components before changing production behavior.

The decomposition deliberately uses two harness layers instead of adding a benchmark-only FRB endpoint to the shipped native API.

### Rust in-process harness

`rust/src/read_path_bench.rs` is compiled only as a Rust test module and is ignored during ordinary test execution. `make benchmark-read-path` invokes it explicitly in release mode.

It measures, for small and medium payloads where applicable:

1. `redb_read_transaction_create`
   - `Database::begin_read()` only.
2. `redb_read_transaction_open_table`
   - `begin_read()` plus opening the `data` table.
3. `redb_point_lookup_borrowed`
   - hit and miss against one stable read snapshot/table, without copying the value.
4. `redb_point_lookup_copy`
   - hit against one stable snapshot/table, including `to_vec()` of the redb value.
5. `messagepack_validate`
   - production `validate_message_pack` on an already available plaintext payload.
6. `vec_payload_copy`
   - standalone native allocation/copy baseline using `to_vec()`.
7. `decrypt_authenticate`
   - ChaCha20Poly1305 decrypt/authenticate with record-key AAD on a prepared ciphertext.
8. `db_get`
   - full in-process production database read path, plaintext/encrypted, hit/miss.
9. `db_contains_key`
   - full in-process production contains path, hit/miss.

The stable-snapshot lookup cases intentionally exclude transaction setup so redb point lookup itself can be separated from per-call transaction creation.

### Dart / FRB harness

`test/read_path_benchmark_test.dart` measures:

- `dart_dxtr_codec_decode` for small/medium payloads;
- `native_adapter_get` through `FrbNativeDxtrApi`, plaintext/encrypted, hit/miss;
- public `Box.get`, plaintext/encrypted, hit/miss;
- `native_adapter_contains_key`, hit/miss;
- public `Box.containsKey`, hit/miss.

Assertions are performed outside the timed loops so test matcher overhead is not included in per-operation timing.

### FRB boundary interpretation

There is intentionally no benchmark-only native `echo` or passthrough function in the production FRB surface.

Therefore PR 1 does **not** claim a directly isolated FRB timer. The approximate FRB/native-adapter region is an **inference** made by comparing the Dart `native_adapter_*` measurements with the corresponding Rust in-process `db_*` measurements collected on the same CI job. That delta also includes Dart async adapter work and cross-harness timer/runtime differences, so it must not be presented as an exact FRB percentage.

If this inference is insufficient to choose a production optimization, a later measurement-only PR may add a more controlled boundary experiment, but only if it can avoid leaving benchmark plumbing in the shipped native API.

## Payloads and scenarios

The initial matrix covers:

```text
payload: small, medium
mode:    plaintext, encrypted where relevant
outcome: hit, miss where relevant
pattern: repeated reads after warmup
```

The Rust medium payload contains roughly 4 KiB of body data. The Dart medium payload likewise contains a 4 KiB string body. Exact encoded byte counts are workload metadata rather than a storage-format contract.

Default local settings:

```text
Rust iterations: 2000
Dart iterations: 1000
samples:          7
```

CI uses a shorter diagnostic smoke configuration:

```text
Rust iterations: 1000
Dart iterations: 500
samples:          5
```

Each operation is warmed before samples are collected. Samples are sorted and the median nanoseconds per operation is emitted.

## Machine-readable evidence

Run:

```bash
make benchmark-read-path
```

Outputs:

```text
build/read-path/rust-read-path.jsonl
build/read-path/dart-read-path.jsonl
```

Each JSONL file contains a context record followed by measurement records. CI additionally archives Flutter, Rust, Cargo, kernel, and CPU metadata under `build/read-path/`.

The `Read-path Benchmark` workflow uploads the directory as the `read-path-benchmark-linux-x64` artifact. Shared-runner timing remains diagnostic and does not introduce a faster/slower release threshold.

## Result recording template

For every production performance change after PR 1, record:

```text
before
  operation / mode / payload / outcome
  median ns/op

after
  operation / mode / payload / outcome
  median ns/op

delta
  absolute and percentage

methodology
  iterations, samples, warmup, harness layer

runner
  Flutter/Dart, rustc/cargo, OS/kernel, CPU metadata when available

correctness validation
  tests and compatibility gates executed
```

Do not compare numbers from different runners as if they were controlled A/B evidence. Prefer before/after runs from the same environment and methodology.

## Current decisions

### Measured fact

Only the previous 0.3 composite point-read measurements are established until the PR 1 workflow completes. New PR 1 numbers must be copied here only after a successful artifact-producing run.

### Inference

The previous evidence identifies the composite native region as dominant relative to Dart decode, but it does not identify which internal component dominates.

### Implemented optimization

None in PR 1. This is intentional.

### Deferred ideas

Until PR 1 evidence is available, do not implement:

- long-lived default read transactions;
- Dart metadata-backed `containsKey`;
- Dart whole-box caching;
- skipped MessagePack validation;
- weakened encrypted authentication;
- storage-format changes;
- speculative buffer/FRB rewrites;
- public multi-key API solely for benchmark convenience.

## Planned 0.5 sequence

```text
PR 1 — read-path benchmark decomposition
PR 2 — single-key read optimization backed by PR 1 evidence
PR 3 — product-grade batch/multi-key read path
PR 4 — read-session investigation; implement only if freshness semantics remain explicit/safe
PR 5 — expanded comparison matrix + 0.5 closure audit
```

PR 3 should benchmark 10 / 100 / 1,000-key reads and avoid N FRB crossings plus N independent read transactions. PR 4 must document redb snapshot lifetime, writer interaction, stale-data semantics, resource retention, Flutter lifecycle, multi-handle behavior, and cross-process expectations even if the conclusion is "do not implement".
