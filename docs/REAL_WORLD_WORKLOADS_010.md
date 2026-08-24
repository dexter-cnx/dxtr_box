# Dxtr_Box 0.10 — Real-world Workload Evidence

## Goal

0.10 adds reproducible application-shaped workload evidence without changing the storage engine merely to win a benchmark.

The milestone answers a narrower question than the existing microbenchmarks:

> How does Dxtr_Box behave when a local application performs realistic mixes of writes, point reads, batch reads, updates, deletes, and query-oriented data access over deterministic datasets?

The benchmark remains diagnostic evidence, not a marketing leaderboard.

## Sequence

```text
PR1 — deterministic real-world workload contract + fixtures
PR2 — Dxtr_Box Dart/FRB scenario runner + JSONL evidence
PR3 — equivalent Rust-native scenario runner + cross-frontend interpretation
PR4 — CI evidence, docs/version sync, and 0.10 closure
```

Do not add runtime optimizations in PR1. Later PRs may propose an optimization only when the scenario evidence identifies a concrete bottleneck and existing conformance tests remain green.

## PR1 workload contract

PR1 defines three deterministic application-shaped datasets under `benchmark/lib/real_world_workloads.dart`.

### 1. Settings/session workload

Small keyspace with frequent point reads and overwrites:

- theme and locale preferences;
- feature flags;
- active workspace/session metadata;
- repeated reads of hot keys;
- periodic overwrite of existing keys.

This workload is intentionally small. It represents app startup and settings access rather than bulk storage.

### 2. Catalog/workspace workload

Medium record set representing items in a local catalog or media workspace:

- stable string IDs;
- status/category fields;
- timestamps and numeric sort fields;
- nested metadata;
- payload text large enough to avoid measuring only trivial scalars;
- deterministic active/archive distribution.

This workload is suitable for mixed point reads, batch reads, updates, deletes, and query/index scenarios in later PRs.

### 3. Activity/event workload

Append-heavy records with a bounded hot window:

- monotonically increasing sequence IDs;
- event type and timestamp;
- actor/source metadata;
- small structured payload;
- deterministic retention boundary for delete batches.

This represents audit/event/history-style local data without introducing time-dependent randomness.

## Determinism rules

Fixtures must be reproducible across machines and runs:

- no wall-clock timestamps;
- no random number generator unless a fixed seed is part of the public workload contract;
- stable keys and record ordering;
- stable field/value distribution;
- stable payload sizes for a given fixture size.

Scenario runners may vary iteration count, but fixture content must not change when the same record count is requested.

## Measurement rules for later PRs

Every scenario result must record enough context to be interpretable:

```text
frontend
scenario
records
iterations/samples where applicable
operation counts
elapsed time / latency summary
build mode
runner/toolchain metadata in CI artifact
```

Cold-open/reopen remains covered by the 0.9 startup benchmark and should not be duplicated unless a scenario needs startup as part of an end-to-end path.

## Correctness before timing

A workload runner must validate its final state before emitting benchmark evidence. Examples:

- overwritten settings expose the latest value;
- deleted catalog records are absent;
- retained catalog records preserve expected IDs and fields;
- event retention deletes only the intended prefix/window;
- batch-read hit/miss ordering follows the established storage contract.

A fast incorrect result is not benchmark evidence.

## Preserved invariants

0.10 must preserve:

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

Use real-world workload evidence to locate costs and regressions. Do not describe cross-engine or cross-frontend deltas as pure storage-engine speedups when the measured boundaries differ.
