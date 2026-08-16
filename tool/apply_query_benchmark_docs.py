from pathlib import Path


def read(path: str) -> str:
    return Path(path).read_text()


def write(path: str, text: str) -> None:
    Path(path).write_text(text)


def append_once(path: str, marker: str, section: str) -> None:
    text = read(path)
    if marker not in text:
        write(path, text.rstrip() + "\n\n" + section.strip() + "\n")


benchmark_doc = '''# Query / Index Benchmark — 0.3

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
'''
Path('docs/QUERY_BENCHMARK_03.md').write_text(benchmark_doc)

append_once(
    'README.md',
    '### Query/index diagnostic benchmark',
    '''### Query/index diagnostic benchmark

Use `make benchmark-query-index` to compare scan and persisted-index execution for equality, range, multi-index AND, and sorted-range queries across configurable dataset sizes. The harness reports JSON diagnostics and deliberately excludes setup/index-backfill time from the query stopwatch. Shared-runner timings are informational rather than release thresholds; see [`docs/QUERY_BENCHMARK_03.md`](docs/QUERY_BENCHMARK_03.md).''',
)

append_once(
    'docs/CODE_WALKTHROUGH.md',
    '## 20. Query/index diagnostic benchmark',
    '''## 20. Query/index diagnostic benchmark

`benchmark/test/query_index_benchmark_test.dart` exercises the public `Box.query(...)` and `createIndex(...)` APIs against equality, range, AND-intersection, and sorted-range workloads. Each scenario is timed once through primary scan and once after the matching persisted indexes exist. Setup and backfill are outside the timed region.

The 2026-08-16 baseline (`31927276095`) shows lower median query time for indexed execution in every measured 100/1,000/5,000-record case. At 5,000 records, range measured 15,125 µs scan vs 6,988 µs indexed, while sorted range measured 16,256 µs vs 7,997 µs. These numbers are diagnostic only.

The result supports keeping candidate narrowing and measuring further before changing the persisted scalar representation. Current index-name-bounded iteration still decodes scalar MessagePack components; a true scalar seek remains a separate storage-format decision with ordering and migration requirements.''',
)

append_once(
    'docs/QUERY_INDEX_03.md',
    '## Query/index benchmark gate',
    '''## Query/index benchmark gate

The 0.3 benchmark harness covers equality, ordered range, multi-index AND intersection, and sorted range in scan/index modes at 100, 1,000, and 5,000 records. It times `Box.query(...)` only; data population and index backfill are excluded. Results are emitted as JSON diagnostics through `make benchmark-query-index`.

Run `31927276095` completed all 24 combinations. Indexed execution had a lower median in every case. The evidence is recorded in `docs/QUERY_BENCHMARK_03.md`. Timing remains informational on shared runners; semantic equivalence, deterministic ordering, and primary-data re-evaluation remain the hard gates.''',
)

handoff = read('docs/PROJECT_HANDOFF.md')
handoff = handoff.replace(
    '## Current snapshot — 0.3 planner selection hardening',
    '## Current snapshot — 0.3 query/index benchmark complete',
)
old = '''Main contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, bounded index-name redb iteration, and single-snapshot query execution. Current branch:\n\n```text\nfeature/0.3-planner-selection-tests\n```\n\nhardens the internal planner by separating persisted-index selection from candidate extraction and adding direct deterministic selection/fallback tests, without changing the public Dart API or FRB shape.'''
new = '''Main contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, bounded index-name redb iteration, single-snapshot query execution, deterministic planner selection, and explicit native `sortBy`. The active 0.3 slice adds a reproducible diagnostic query/index benchmark matrix on `feature/0.3-query-benchmarks`; it does not change public query semantics or the FRB shape.'''
handoff = handoff.replace(old, new)
handoff = handoff.replace(
    '''4. Define an explicit public `sortBy` contract separately.\n5. Add focused query/index benchmark scenarios now that planner and execution semantics are stable.\n6. Continue point-get/contains performance diagnosis independently.\n7. Keep encrypted-index design, cross-commit size policy, and Dart 3.13 tree shaking separate.''',
    '''4. Completed: explicit public `sortBy` contract and deterministic native execution.\n5. Completed: focused query/index benchmark matrix with machine-readable diagnostic output.\n6. Next: point-get/contains performance diagnosis independently.\n7. Then: Hive CE migration design/implementation and 0.3 closure audit.\n8. Keep encrypted-index design, cross-commit size policy, and Dart 3.13 tree shaking separate.''',
)
append = '''\n\n### Query/index benchmark evidence\n\n`make benchmark-query-index` now measures equality, range, AND-intersection, and sorted-range queries in scan/index modes at 100/1,000/5,000 records. Run `31927276095` completed the full 24-case matrix. At 5,000 records the median scan/index measurements were: equality 15,887/10,649 µs, range 15,125/6,988 µs, AND intersection 15,511/8,739 µs, and sorted range 16,256/7,997 µs. Shared-runner timings are diagnostic, not hard thresholds.\n\nThe evidence supports persisted-index candidate narrowing but does not by itself justify an order-preserving persisted scalar format. The immediate 0.3 sequence is point-get/contains diagnosis, Hive CE migration, then closure audit.\n'''
if '### Query/index benchmark evidence' not in handoff:
    handoff = handoff.rstrip() + append
write('docs/PROJECT_HANDOFF.md', handoff)
