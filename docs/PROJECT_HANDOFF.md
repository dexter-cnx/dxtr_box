# dxtr_box Project Handoff

## Product

**dxtr_box — Native local database for Flutter and Rust, forged in Rust. By Dxtr.**

`dxtr_box` is a compact Rust/redb local database engine with a Flutter/Dart frontend and a first-class native Rust frontend. It is not positioned as a Hive/Hive CE replacement; Hive CE remains optional migration tooling, compatibility reference, and benchmark peer.

## Stable runtime/package contract

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Package version:         1.1.0
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          meta[format_version] = dxtr_box/1
native profiles:         minimal | encryption | full
```

`full` remains the default. Do not add a fourth native profile. Dart 3.13 recorded-use/native tree shaking remains deferred unless explicitly reprioritized with evidence.

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
- 1.0 Stabilization / Release Readiness
- **1.1 Post-release Evidence / Reliability**

1.0 / 1.1 sequence:

```text
1.0 PR1 contract-freeze audit + stronger guards                          merged (#57)
1.0 PR2 public API semantic regression inventory + tests                 merged (#61)
1.0 PR3 release-candidate consumer / migration / upgrade evidence        merged (#62)
1.0 PR4 final release audit, docs sync, version 1.0.0                    merged (#63)
post-release handoff sync                                                 merged (#64)
1.1 planning baseline                                                    merged (#65)
1.1 PR1 registry-resolved external consumer verification                 merged (#66)
1.1 PR2 native concurrency + reopen evidence                             merged (#67)
1.1 PR3 native-size / tree-shaking decision evidence                     merged (#68)
1.1 PR4 Dart isolate / FRB concurrency evidence                          merged (#69)
1.1 closure audit + docs + version 1.1.0                                 merged (#70)
1.2 planning baseline                                                    current
```

See:

- `docs/RELEASE_AUDIT_100.md`
- `docs/ROADMAP_11.md`
- `docs/POST_RELEASE_REGISTRY_VERIFICATION_11.md`
- `docs/CONCURRENCY_EVIDENCE_11.md`
- `docs/NATIVE_SIZE_DECISION_11.md`
- `docs/DART_ISOLATE_CONCURRENCY_EVIDENCE_11.md`
- `docs/RELEASE_AUDIT_110.md`
- `docs/ROADMAP_12.md`

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

## 1.0 + 1.1 evidence

The stable line is guarded by executable evidence rather than documentation-only claims:

- exact Dart export and Rust root/wildcard contract guards;
- query model and fluent-builder semantic regression tests;
- native persistence and reopen coverage;
- encrypted reopen and wrong/missing-key rejection;
- Hive CE migration destination reservation/lifecycle coverage;
- staged published payload validation;
- generated consumer builds on Android, iOS, macOS, Linux, and Windows;
- FRB generated binding reproducibility;
- exact `minimal | encryption | full` Rust profile testing;
- native-size regression policy plus reproducible Linux/macOS evaluation evidence;
- guaranteed native concurrent reader/writer overlap and durable reopen;
- independent Dart isolate / FRB shared-storage visibility and close/reopen durability;
- package docs + pub dry-run;
- benchmark correctness and diagnostic smoke.

The durable format remains `dxtr_box/1`; 1.1 introduced no storage migration.

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

1.1 additionally retains:

- manual `Native Size Evaluation` evidence on Linux/macOS, retaining TSV, generated `rust/Cargo.lock`, and locked Cargo metadata;
- dedicated `Dart Isolate Concurrency` CI through the real Dart -> FRB -> Rust path.

## Preserved non-goals

Do not turn post-1.1 maintenance into:

- GPUI integration inside core;
- Tokio/runtime commitment;
- ORM/schema/model code generation;
- cloud sync/CRDT/network database functionality;
- storage-format redesign without an explicit migration plan;
- query-engine rewrite;
- encryption redesign;
- a fourth native profile;
- broad Dart API redesign.

## Next active work: 1.2 evidence-driven planning

Do not manufacture a 1.2 feature list merely to continue development. `docs/ROADMAP_12.md` is the decision baseline: hosted 1.1.0 registry verification remains the first external release gate, while developer inspection tooling, migration/interoperability, recorded-use/native tree shaking, stronger isolate/watch/order semantics, and Web strategy remain conditional candidates.

A candidate moves from investigation to implementation only when there is a concrete consumer/reliability/maintenance need, executable evidence, preserved compatibility, and a smaller/saner design than introducing parallel storage semantics.

Registry publication remains an external release step and must not be inferred merely from repository version `1.1.0`. If/when the package is published, run the registry-resolved consumer verification against the actual hosted `1.1.0` package.

## Compatibility rule

Treat the Dart public API, Rust root API, package identities, native profiles, and `dxtr_box/1` durable format as compatibility-sensitive contracts. Breaking changes require an explicit versioning/migration decision rather than incidental refactoring.

Correctness, durability, authenticated encryption, cross-process/cross-frontend visibility, compatibility, and evidence quality take priority over feature count or benchmark wins.
