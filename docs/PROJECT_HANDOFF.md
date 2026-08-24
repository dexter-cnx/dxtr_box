# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

Dxtr_Box is a compact Rust/redb local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. It is not positioned as a Hive/Hive CE replacement; Hive CE remains optional migration tooling, compatibility reference, and a benchmark peer.

## Stable runtime/package contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Package version:         0.10.0-dev.1
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          meta[format_version] = dxtr_box/1
native profiles:         minimal | encryption | full
```

`full` remains the default. Do not add a fourth native profile. Dart 3.13 recorded-use/native tree shaking remains deferred unless explicitly reprioritized.

## Milestone state

Completed:

- 0.3 Query / Index / Migration
- 0.4 Production Hardening
- 0.5 Performance / Read-path Optimization
- 0.6 Query / Index + Encryption Hardening
- 0.7 Query Ergonomics
- 0.8 Rust-native API / Multi-frontend Foundation
- 0.9 Conformance & Startup Maturity
- **0.10 Real-world Workload Evidence** — closure is PR #60

0.10 sequence:

```text
PR1  deterministic real-world fixtures                                      merged
PR2  Dart/FRB workload runner + JSONL evidence                              merged
PR3  Rust-native equivalent runner + cross-frontend interpretation          merged
PR4  reproducible CI artifact + docs/version synchronization                current closure PR (#60)
```

See:

- `docs/REAL_WORLD_WORKLOADS_010.md`
- `docs/REAL_WORLD_CROSS_FRONTEND_010.md`
- `docs/RELEASE_AUDIT_010.md`

## Architecture

Required dependency direction:

```text
Dart API -> FRB adapter ----┐
                            ├-> shared authoritative Rust core -> redb
Rust API -------------------┘
```

The Rust frontend does not wrap Dart or FRB. GPUI is only a potential downstream consumer and is not a Dxtr_Box dependency.

One canonical storage engine means one durable contract:

```text
{box}.dxtr
meta[format_version] = dxtr_box/1
@dxtr:* durable MessagePack tags where already defined
```

Primary records are authoritative. Persisted indexes are derived state maintained transactionally with primary mutations.

## Public frontends

Dart consumers use `Box`, `BoxStore`, `BoxQuery`, `BoxQueryBuilder`, and optional authoring metadata `BoxField<T>`. `DxtrBox` remains only as a deprecated source-compatibility shim where required.

Native Rust consumers use `DxtrBox`, `BoxHandle`, `Record`, `IndexDefinition`, `DxtrBoxError`, and full-profile query types. The Rust API is synchronous and has no Tokio commitment.

Both frontends converge onto the same canonical query representation, planner, redb storage path, encryption path, and persisted indexes.

## 0.10 evidence path

Run:

```bash
bash tool/real_world_workloads.sh
```

The same deterministic settings/session, catalog/workspace, and activity/event workloads run through both frontends.

Outputs:

```text
build/real-world/rust-native.jsonl
build/real-world/dart-frb.jsonl
build/real-world/rust-native.log
build/real-world/dart-frb.log
build/real-world/toolchain.txt
```

The `Real-world Workloads` GitHub Actions workflow runs the same evidence script and uploads the directory as a retained artifact.

Evidence rules:

- correctness before timing;
- Rust and Dart fixture shapes/values must remain equivalent;
- exactly three scenario records per frontend;
- record/sample/build/toolchain context must match before comparison;
- cross-frontend deltas are boundary diagnostics, not pure storage-engine speedups or marketing claims.

## CI / local preflight

Before push:

```bash
make preflight
```

Tracked formatting guard installation:

```bash
bash tool/install_git_hooks.sh
```

Full merge validation retains format/analyze/tests, minimum SDK, all three Rust profiles, native integration, migration/query/index/crash-reopen regression, FRB generation reproducibility, native-size policy, package/pub readiness, benchmark correctness, and staged Android/iOS/macOS/Linux/Windows consumers.

## Preserved non-goals

Do not turn stabilization work into:

- GPUI integration inside core;
- Tokio/runtime commitment;
- ORM/schema/model code generation;
- cloud sync/CRDT/network database functionality;
- storage-format redesign;
- query-engine rewrite;
- encryption redesign;
- a fourth native profile;
- broad Dart API redesign.

## Next active milestone: 1.0 stabilization

After PR #60 merges, resume PR #57 (`1.0 PR1: contract freeze audit and stronger release guards`).

Required first steps:

1. rebase/rebuild #57 cleanly on current `main`;
2. fix Cargo contract parsing so `[package].name` and `[lib].name` are independently guarded;
3. make the Rust root export guard reject unexpected additions as well as missing exports;
4. run format/preflight and resolve review threads;
5. continue the 1.0 readiness sequence without adding unrelated features.

Planned 1.0 sequence:

```text
PR1 contract-freeze audit + stronger guards
PR2 public API semantic regression inventory + missing compatibility tests
PR3 release-candidate published-consumer / migration / upgrade evidence
PR4 final release audit, docs sync, version 1.0.0
```

## Working rule

Correctness, durability, authenticated encryption, cross-process/cross-frontend visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.
