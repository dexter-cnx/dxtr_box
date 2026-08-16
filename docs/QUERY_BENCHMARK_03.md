# Query / Index Benchmark — 0.3

## Purpose

This benchmark is a diagnostic tool for the 0.3 query/index execution path. It is not a latency SLA and shared GitHub runner timings are not used as a hard pass/fail regression threshold.

The harness answers a narrower architectural question: after query semantics, planner selection, single-snapshot execution, and deterministic sorting are stable, does persisted-index candidate narrowing materially reduce native query time enough to guide the next optimization decision?

## Harness

Run locally with:

```bash
make benchmark-query-index
```

Defaults:

```text
dataset sizes: 100, 1000, 5000 records
samples:       3 measured runs after one warmup
scenarios:     equality, range, AND intersection, sorted range
modes:         primary scan, persisted-index candidate narrowing
```

Setup, writes, and index backfill occur before the stopwatch. The timed region is only `Box.query(...)`. Each sample uses an isolated box and the same public Dart query/index API used by applications.

Results are emitted as machine-readable JSON lines prefixed with `DXTR_BOX_QUERY_BENCHMARK`.

## Baseline evidence

GitHub Actions run `31927276095` on 2026-08-16 completed the full matrix using Flutter 3.47.0 / Dart 3.13.0 and the release Rust library. Artifact `query-index-benchmark` (artifact id `9258233970`) contains the JSONL output.

Median query latency in microseconds:

| records | scenario | scan | indexed | scan / indexed |
|---:|---|---:|---:|---:|
| 100 | equality | 1,473 | 550 | 2.68x |
| 100 | range | 695 | 477 | 1.46x |
| 100 | AND intersection | 702 | 511 | 1.37x |
| 100 | sorted range | 641 | 457 | 1.40x |
| 1,000 | equality | 3,697 | 2,150 | 1.72x |
| 1,000 | range | 3,499 | 1,555 | 2.25x |
| 1,000 | AND intersection | 3,359 | 1,995 | 1.68x |
| 1,000 | sorted range | 3,540 | 1,793 | 1.97x |
| 5,000 | equality | 15,887 | 10,649 | 1.49x |
| 5,000 | range | 15,125 | 6,988 | 2.16x |
| 5,000 | AND intersection | 15,511 | 8,739 | 1.77x |
| 5,000 | sorted range | 16,256 | 7,997 | 2.03x |

## Interpretation

Persisted-index narrowing is beneficial in every measured scenario and dataset size in this run. The strongest 5,000-record gains are range and sorted-range queries, where candidate narrowing roughly halves measured query time.

Equality improves less at 5,000 records than range does. This is consistent with the current storage design: lookup is bounded to one index-name prefix, but entries inside that prefix are still decoded and semantically compared. The benchmark therefore identifies scalar-level seek as a plausible future optimization target without proving that a new persisted encoding is worth its compatibility and rebuild cost.

No storage-format change is justified by one shared-runner sample. Any order-preserving scalar representation must still define exact signed/unsigned/float/string ordering, versioning, rebuild/migration behavior, and scan/index equivalence before implementation.

## Regression policy

- Correctness tests remain hard gates.
- This benchmark must continue to complete and emit the expected matrix.
- Shared-runner timing values are informational.
- Do not weaken durability, skip authoritative primary rechecks, or add a Dart whole-box cache to improve benchmark numbers.
- A future hard performance budget requires controlled hardware, repeated historical baselines, and an explicit variance policy.
