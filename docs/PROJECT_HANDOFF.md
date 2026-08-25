# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a compact Rust/redb local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. It is not positioned as a Hive/Hive CE replacement; Hive CE remains optional migration tooling, compatibility reference, and benchmark peer.

## Stable 1.0 runtime/package contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Package version:         1.0.0
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
- 0.10 Real-world Workload Evidence
- **1.0 Stabilization / Release Readiness**

1.0 sequence:

```text
PR1 contract-freeze audit + stronger guards                              merged (#57)
PR2 public API semantic regression inventory + compatibility tests       merged (#61)
PR3 release-candidate published-consumer / migration / upgrade evidence  merged (#62)
PR4 final release audit, docs sync, version 1.0.0                         merged (#63)
```

See:

- `docs/RELEASE_READINESS_10.md`
- `docs/PUBLIC_API_SEMANTIC_REGRESSION_10.md`
- `docs/RELEASE_CANDIDATE_EVIDENCE_10.md`
- `docs/RELEASE_AUDIT_100.md`

## Architecture

Required dependency direction:

```text
Dart API -> FRB adapter ----┐
                            ├-> shared authoritative Rust core -> redb
Rust API -------------------┘
```

The Rust frontend does not wrap Dart or FRB. GPUI is only a potential downstream consumer and is not a `dxtr_box` dependency.

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

## 1.0 release evidence

The 1.0 release is guarded by executable evidence rather than documentation-only claims:

- exact Dart export and Rust root/wildcard contract guards;
- query model and fluent-builder semantic regression tests;
- native persistence and reopen coverage;
- encrypted reopen and wrong/missing-key rejection;
- Hive CE migration destination reservation/lifecycle coverage;
- staged published payload validation;
- generated consumer builds on Android, iOS, macOS, Linux, and Windows;
- FRB generated binding reproducibility;
- exact `minimal | encryption | full` Rust profile testing;
- native-size regression policy;
- package docs + pub dry-run;
- benchmark correctness and diagnostic smoke.

The durable format remains `dxtr_box/1`; 1.0 introduces no storage migration.

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

Do not turn post-1.0 maintenance into:

- GPUI integration inside core;
- Tokio/runtime commitment;
- ORM/schema/model code generation;
- cloud sync/CRDT/network database functionality;
- storage-format redesign without an explicit migration plan;
- query-engine rewrite;
- encryption redesign;
- a fourth native profile;
- broad Dart API redesign.

## Post-1.0 rule

Treat the Dart public API, Rust root API, package identities, native profiles, and `dxtr_box/1` durable format as compatibility-sensitive contracts. Breaking changes require an explicit versioning/migration decision rather than incidental refactoring.

Next work should begin with post-release verification and a separately justified 1.1 backlog. New features must be evaluated against the stable 1.0 contract before implementation.

Correctness, durability, authenticated encryption, cross-process/cross-frontend visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.
