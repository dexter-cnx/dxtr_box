# Dxtr_Box 0.10 Release Audit

## Milestone

0.10 — Real-world Workload Evidence is complete when PR4 merges.

The milestone adds application-shaped, deterministic workload evidence without changing the authoritative Rust/redb engine merely to improve benchmark numbers.

## Delivered sequence

- PR1: deterministic settings/session, catalog/workspace, and activity/event fixtures.
- PR2: Dart/FRB scenario runner with machine-readable JSONL evidence and correctness checks.
- PR3: equivalent Rust-native runner using fixture shapes and deterministic values matching the Dart fixtures, plus cross-frontend interpretation rules.
- PR4: reproducible CI evidence workflow, artifact upload, documentation sync, and package version sync.

## Evidence workflow

Run locally with:

```bash
bash tool/real_world_workloads.sh
```

The runner writes:

```text
build/real-world/rust-native.jsonl
build/real-world/dart-frb.jsonl
build/real-world/rust-native.log
build/real-world/dart-frb.log
build/real-world/toolchain.txt
```

The GitHub Actions `Real-world Workloads` workflow runs the same script on Ubuntu and uploads `build/real-world` as an artifact.

Each frontend must emit exactly three scenario records:

```text
settings_session
catalog_workspace
activity_event
```

Each record identifies the frontend, scenario, record count, sample count, logical operation count/unit, elapsed samples, latency summary, and build mode. Toolchain metadata is stored with the artifact.

## Interpretation

The evidence is diagnostic, not a marketing leaderboard. Dart/FRB and Rust-native results may be compared only when fixture sizes, sample counts, build modes, and toolchain context are equivalent. Deltas include frontend and FFI boundary costs; they must not be described as pure storage-engine speedups.

## Preserved contracts

0.10 does not alter:

- authoritative Rust/redb storage ownership;
- durable format `dxtr_box/1`;
- Dart >= 3.4.0 < 4.0.0;
- Flutter >= 3.22.0;
- flutter_rust_bridge 2.8.0;
- redb 2.1.0;
- exactly `minimal | encryption | full` native profiles;
- encryption semantics;
- query/index engine semantics;
- public Dart/Rust architecture boundaries.

No cache, storage-format redesign, query-engine rewrite, new encryption design, fourth profile, GPUI dependency, ORM, or sync layer is introduced.

## Package version

Milestone closure advances the development package version to `0.10.0-dev.1`.

## Next milestone

After 0.10 merges, resume 1.0 stabilization/release readiness. The existing 1.0 contract-freeze work in PR #57 should be rebased onto current `main`, its review findings resolved, and the 1.0 readiness sequence continued without broadening scope.
