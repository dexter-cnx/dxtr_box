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

The public/native deltas approximate Dart codec and wrapper overhead. Plaintext/encrypted native deltas approximate native decrypt/authentication overhead. The native timings still include FRB boundary cost plus redb lookup and value copying; no diagnostic-only FRB API is added because changing the native surface would perturb the path being measured.

## Dataset and timing

- 1,000 records per plaintext/encrypted box
- default 500 iterations per timing sample
- default 5 timing samples after warmup
- median reported as microseconds and normalized nanoseconds per operation
- configuration: `POINT_READ_ITERATIONS` and `POINT_READ_SAMPLES`
- machine-readable prefix: `DXTR_BOX_POINT_READ_DIAGNOSIS `

## Decision rules

1. Do not replace authoritative redb point reads with Dart metadata guesses for `get`.
2. `containsKey` may only use metadata as an optimization if semantics remain correct across multiple handles and native watch synchronization.
3. Do not add a new public profile or change the public API for this diagnosis.
4. If the dominant cost is FRB boundary overhead, prefer batching only when a real public workload requires it; do not disguise a point lookup as a whole-box scan.
5. If codec/decrypt cost dominates, optimize that layer independently and preserve the stored format unless evidence justifies migration.

## Status

Harness staged on `feature/0.3-point-read-diagnosis`; baseline evidence is pending the diagnostic workflow run.
