# Dxtr_Box 0.9 — Startup Benchmark Evidence

## Decision

Do **not** add a startup fast path in 0.9.

The hosted Linux x64 benchmark shows existing open/reopen cost is sub-millisecond and does not grow materially with record count or persisted-index count across the tested matrix. Adding fingerprint metadata, cache state, or another startup branch would add correctness and compatibility surface without evidence of a meaningful bottleneck.

## Evidence

GitHub Actions run: `Read-path Benchmark #149` (`32678953193`).

Environment captured by the workflow:

- Ubuntu 24.04 hosted runner, Linux x86_64;
- Flutter 3.47.1 / Dart 3.13.1;
- rustc 1.98.0;
- release Rust build;
- 100 reopen samples per case.

Matrix results in microseconds:

| records | indexes | first open | reopen p50 | reopen p95 | max |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 0 | 593.394 | 603.092 | 686.257 | 1893.482 |
| 0 | 1 | 595.318 | 585.309 | 659.628 | 677.210 |
| 0 | 4 | 545.816 | 598.183 | 703.158 | 962.791 |
| 1,000 | 0 | 648.647 | 569.139 | 623.169 | 791.863 |
| 1,000 | 1 | 578.887 | 573.668 | 666.690 | 859.449 |
| 1,000 | 4 | 649.969 | 440.670 | 612.309 | 1807.934 |
| 10,000 | 0 | 484.852 | 467.480 | 601.970 | 742.862 |
| 10,000 | 1 | 544.483 | 456.490 | 507.113 | 588.745 |
| 10,000 | 4 | 509.929 | 448.475 | 532.741 | 1210.182 |

The highest observed p95 is about 0.703 ms. The 10,000-record cases are not slower than the empty or 1,000-record cases, and four persisted indexes do not create a meaningful startup trend. Max values are treated as hosted-runner noise rather than a scaling signal because p50/p95 remain stable.

## What the benchmark covers

Each fixture is created, populated, indexed as configured, and closed before timing. The diagnostic then measures:

1. first open after fixture preparation/close;
2. repeated close/open cycles;
3. 0 / 1,000 / 10,000 records;
4. 0 / 1 / 4 persisted indexes.

The benchmark intentionally exercises the existing public Rust-native facade and shared core. It does not introduce benchmark-only storage shortcuts.

## Consequence

0.9 keeps the current startup path unchanged:

- format compatibility handling remains authoritative;
- legacy missing format metadata continues to use the established initialization path;
- encryption/key validation is never skipped;
- reduced profiles still reject persisted indexes safely;
- `full` still ensures index tables without schema registration;
- no configuration fingerprint is persisted;
- no storage-format change is required.

A startup fast path may be reconsidered only if later profiling on realistic applications or materially larger configuration surfaces demonstrates a measurable bottleneck.