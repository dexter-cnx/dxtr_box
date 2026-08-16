# dxtr_box 0.3 Point-read diagnosis

## Goal

Measure where point-read cost is spent before changing `Box.get` or `Box.containsKey`.
This slice is diagnostic first: measurements may justify an implementation change, but timing from a shared GitHub runner is not a release SLA or a hard regression threshold.

## Matrix

`make diagnose-point-read` measures repeated operations after setup and warmup:

- public plaintext `Box.get` hit
- native plaintext `get` hit
- MessagePack decode-only work using an already-fetched payload
- public/native plaintext `get` miss
- public/native `containsKey` hit and miss
- pure-Dart metadata-key membership as a local baseline
- public/native encrypted `get` hit

The public/native deltas approximate Dart wrapper/codec overhead. The native timings still include FRB boundary cost plus redb read-transaction setup, lookup, validation/decrypt when applicable, and value copying. No diagnostic-only FRB API is added because changing the native surface would perturb the path being measured.

## Dataset and timing

- 1,000 records per plaintext/encrypted box
- default 500 iterations per timing sample
- default 5 timing samples after warmup
- median reported as microseconds and normalized nanoseconds per operation
- configuration: `POINT_READ_ITERATIONS` and `POINT_READ_SAMPLES`
- machine-readable prefix: `DXTR_BOX_POINT_READ_DIAGNOSIS `

## Baseline evidence

Authoritative diagnostic run: GitHub Actions `31928485185`, artifact `point-read-diagnosis` (`9258590573`). The run used Flutter 3.47.0 / Dart 3.13.0 on an Ubuntu shared runner.

Median time per operation derived from 500 operations × 5 samples:

| operation | median µs/op |
| --- | ---: |
| public plaintext `get` hit | 287.078 |
| native plaintext `get` hit | 225.726 |
| MessagePack decode only | 6.018 |
| public plaintext `get` miss | 219.968 |
| native plaintext `get` miss | 209.424 |
| public `containsKey` hit | 215.482 |
| native `containsKey` hit | 193.830 |
| public `containsKey` miss | 193.884 |
| native `containsKey` miss | 195.628 |
| Dart metadata membership hit | 6.532 |
| public encrypted `get` hit | 229.262 |
| native encrypted `get` hit | 207.664 |

These are diagnostic observations only. In particular, encrypted reads happened to measure slightly faster than plaintext reads on this shared-runner sample, so this run cannot isolate a meaningful crypto penalty; that delta is treated as measurement noise rather than evidence that encryption is faster.

## Diagnosis

1. MessagePack decode is not the dominant point-read cost in this workload. Decode-only is about 6 µs/op while the native plaintext hit path is about 226 µs/op.
2. The dominant measured region is the existing native point-call path: FRB call/response overhead plus redb read-transaction setup, point lookup, validation/decrypt where applicable, and payload copying.
3. Public-wrapper overhead exists but is secondary to the native point-call path. The plaintext hit sample was about 61 µs/op above the direct native adapter sample, but this includes Dart async/wrapper/assertion effects and is not a stable standalone FRB estimate.
4. Dart metadata membership is much cheaper than authoritative native `containsKey`, but `_metadata.keys` is a convenience snapshot, not durable truth across processes. Replacing native `containsKey` with metadata would trade correctness for benchmark speed and is rejected.
5. Hit/miss and plaintext/encrypted differences are small enough relative to shared-runner variability that this evidence does not justify codec, crypto, or storage-format changes.

## Decision

No point-read implementation change is justified for 0.3 from this diagnostic alone.

Keep:

- `Box.get` as an authoritative native/redb point read followed by `DxtrCodec.decode`;
- `Box.containsKey` as an authoritative native/redb lookup;
- current stored MessagePack/encryption formats;
- exactly three native profiles.

If a real workload later shows point-read throughput is a product bottleneck, measure a batch/multi-get API or a safe native read-session design separately. Do not disguise point lookup as a whole-box Dart cache and do not weaken cross-handle/process correctness for local metadata speed.

## Decision rules

1. Do not replace authoritative redb point reads with Dart metadata guesses for `get`.
2. Do not replace authoritative `containsKey` with metadata unless a future design proves cross-handle and cross-process freshness semantics.
3. Do not add a new public profile or change the public API for this diagnosis.
4. If repeated boundary crossings dominate a demonstrated workload, benchmark batching explicitly before introducing it.
5. Optimize codec/crypto independently only when isolated evidence shows they dominate; preserve the stored format unless migration cost is justified.

## Status

Diagnosis complete. CI #238 (`31928486808`) and diagnostic run `31928485185` are green. Final PR checks are rerun after the documentation-only finalize commit; the 0.3 decision remains to retain authoritative point-read semantics and proceed to the Hive CE migration slice rather than add speculative performance changes.
