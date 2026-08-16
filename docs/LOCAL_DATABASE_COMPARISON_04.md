# Local Database Comparison — 0.4

## Purpose

PH-03 broadens the existing dxtr_box vs Hive CE smoke benchmark into a reproducible Flutter local-database comparison matrix without turning runner timings into release gates.

The comparison has two separate responsibilities:

1. **Correctness gate** — equivalent CRUD, deletion, close/reopen, and persisted-read behavior must converge to the same canonical state.
2. **Diagnostic timing matrix** — identical logical scenarios are measured and emitted as evidence, but no engine is required to be faster than another.

## Engines

The initial PH-03 matrix contains four backends:

| Engine | Role in the matrix |
| --- | --- |
| `dxtr_box` | Rust/redb candidate under production hardening |
| `hive_ce` | closest box-style compatibility reference |
| `sembast` | document-oriented Dart/Flutter NoSQL reference |
| `sqflite_ffi` | SQLite relational embedded reference through `sqflite_common_ffi` |

Comparison-only packages live under `benchmark/`. They do not become runtime dependencies of the published `dxtr_box` package and do not change the root Dart/Flutter SDK floor.

The benchmark package pins the comparison versions so a result remains attributable to a known dependency set rather than silently changing when pub resolution changes.

## Correctness hard gate

`benchmark/test/local_database_correctness_test.dart` runs one common workload through all four adapters:

```text
open
  -> batch insert shared payloads
  -> overwrite one record
  -> contains(existing) / contains(missing)
  -> point read overwritten record
  -> delete deterministic key subset
  -> close
  -> reopen
  -> verify deleted keys remain absent
  -> verify retained keys and values remain present
  -> compare final snapshot across all engines
```

A mismatch fails CI. This is a semantic/durability smoke gate, not a claim that the four databases expose identical APIs or transaction models.

Run locally:

```bash
make benchmark-comparison-correctness
```

## Diagnostic timing matrix

`benchmark/test/local_database_benchmark_test.dart` measures these scenarios:

```text
sequential_put
batch_put
point_get
contains
delete_all
reopen_read
```

Each engine receives a warmup followed by three measured samples. The report emits:

```json
{
  "engine": "dxtr_box",
  "scenario": "point_get",
  "operations": 200,
  "samples": [0, 0, 0],
  "median_us": 0,
  "min_us": 0,
  "max_us": 0
}
```

The zeroes above are schema examples only, not benchmark results.

Run locally:

```bash
make benchmark-comparison
```

Override the operation count with:

```bash
make benchmark-comparison COMPARISON_OPS=1000
```

## CI evidence

The native Linux CI lane runs:

```text
native integration
Hive CE migration fixture
existing dxtr_box vs Hive CE smoke benchmark
PH-03 four-engine correctness gate
PH-03 four-engine diagnostic smoke
```

The diagnostic smoke writes JSONL evidence to:

```text
benchmark/build/comparison/local-database-comparison.jsonl
```

CI uploads it as the `local-database-comparison` artifact.

## Interpretation rules

- Correctness failures are release blockers.
- Failure to execute a diagnostic scenario is a test/harness failure and must be investigated.
- Raw timing differences are **not** pass/fail thresholds.
- GitHub-hosted runner timings must not be presented as stable product performance numbers.
- Results are only directly comparable when engine versions, workload, operation count, samples, platform, architecture, and toolchain context are known.
- A faster result does not override durability, encryption, storage correctness, package compatibility, or API constraints.
- Performance optimization work should start only when repeated measurements expose a meaningful product bottleneck.

## Scope limits

PH-03 does not attempt to normalize every feature across engines. In particular, query planners, secondary indexes, encryption models, reactive APIs, code generation, schema systems, and Web backends differ substantially and need separate capability-level evaluation when they become release-relevant.

This matrix is an engineering comparison harness, not a marketing leaderboard.
