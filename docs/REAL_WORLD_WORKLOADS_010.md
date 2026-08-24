# Dxtr_Box 0.10 — Real-world Workload Evidence

## Goal

0.10 adds reproducible application-shaped workload evidence without changing the storage engine merely to win a benchmark.

The milestone answers a narrower question than the existing microbenchmarks:

> How does Dxtr_Box behave when a local application performs realistic mixes of writes, point reads, batch reads, updates, deletes, and query-oriented data access over deterministic datasets?

The benchmark remains diagnostic evidence, not a marketing leaderboard.

## Sequence

```text
PR1 — deterministic real-world workload contract + fixtures                         complete
PR2 — Dxtr_Box Dart/FRB scenario runner + JSONL evidence                           complete
PR3 — equivalent Rust-native scenario runner + cross-frontend interpretation       complete
PR4 — CI evidence, docs/version sync, and 0.10 closure                             current closure PR
```

## Workload contract

Three deterministic application-shaped datasets live under `benchmark/lib/real_world_workloads.dart`.

### 1. Settings/session workload

Small keyspace with frequent point reads and overwrites:

- theme and locale preferences;
- feature flags;
- active workspace/session metadata;
- repeated reads of hot keys;
- periodic overwrite of existing keys.

### 2. Catalog/workspace workload

Medium record set representing items in a local catalog or media workspace:

- stable string IDs;
- status/category fields;
- timestamps and numeric sort fields;
- nested metadata;
- deterministic payload text;
- deterministic active/archive distribution.

### 3. Activity/event workload

Append-heavy records with a bounded hot window:

- monotonically increasing sequence IDs;
- event type and timestamp;
- nested actor/source metadata;
- deterministic structured payload;
- deterministic retention boundary for delete batches.

## Determinism rules

Fixtures are reproducible across machines and runs:

- no wall-clock timestamps in fixture content;
- no random drift;
- stable keys and record ordering;
- stable field/value distribution;
- stable payload sizes for a given fixture size;
- Rust-native fixture shapes and deterministic values mirror the Dart fixtures.

## Measurement contract

Every scenario result records enough context to be interpretable:

```text
frontend
scenario
records
samples
operations_per_sample
operation_unit
elapsed_us
median_us
min_us
max_us
build mode
```

CI artifacts additionally contain runner/toolchain metadata.

Cold-open/reopen remains covered by the 0.9 startup benchmark and is not duplicated here.

## Correctness before timing

A workload runner validates state before evidence is accepted:

- overwritten settings expose the latest value;
- catalog batch-read ordering matches requested keys;
- catalog records preserve stable identity fields;
- deleted catalog records are absent;
- event retention removes only the intended prefix/window;
- the first retained activity record remains present.

A fast incorrect result is not benchmark evidence.

## Reproducible evidence

Run locally:

```bash
bash tool/real_world_workloads.sh
```

Outputs:

```text
build/real-world/rust-native.jsonl
build/real-world/dart-frb.jsonl
build/real-world/rust-native.log
build/real-world/dart-frb.log
build/real-world/toolchain.txt
```

Each frontend must emit exactly three records:

```text
settings_session
catalog_workspace
activity_event
```

The `Real-world Workloads` GitHub Actions workflow runs the same script on Ubuntu and uploads the complete `build/real-world` directory as an artifact.

## Preserved invariants

0.10 preserves:

- one authoritative Rust/redb engine;
- `dxtr_box/1` durable format;
- Dart >= 3.4 / Flutter >= 3.22;
- flutter_rust_bridge 2.8.0;
- redb 2.1.0;
- exactly `minimal | encryption | full`;
- authenticated encryption semantics;
- cross-frontend conformance;
- no Dart whole-box cache;
- no GPUI dependency in the core package;
- no ORM/schema/model generation requirement.

## Non-goals

0.10 is not:

- a storage-format redesign;
- a query-engine rewrite;
- a new encryption design;
- an ORM benchmark;
- a cloud/sync benchmark;
- a fourth native profile;
- permission to tune workloads to favor Dxtr_Box.

## Interpretation rule

Use real-world workload evidence to locate costs and regressions. Do not describe cross-frontend deltas as pure storage-engine speedups: Dart/FRB includes frontend and FFI-boundary cost that Rust-native does not.

Only compare evidence when record counts, sample counts, build modes, and runner/toolchain context match.

## 0.10 closure

0.10 closes with evidence infrastructure rather than a speculative optimization. No new cache, fast path, storage metadata, query engine, or durable format is introduced.

Package version at closure: `0.10.0-dev.1`.

See `docs/RELEASE_AUDIT_010.md` for the closure audit. The next active milestone after this PR merges is 1.0 stabilization/release readiness.
