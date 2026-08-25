# dxtr_box 1.1 Release Audit

## Decision

`dxtr_box 1.1.0` is a compatibility-preserving post-1.0 evidence release. The milestone closes without a storage migration, public API redesign, SDK-floor increase, or new runtime feature family.

## Stable contract retained

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

The 1.0 Dart public API, Rust root API, durable files, encryption/query/index semantics, package identities, and exactly three native profiles remain compatibility-sensitive.

## 1.1 evidence sequence

### PR1 — registry-resolved consumer verification

Added a manual hosted-registry verification path for clean external consumers. This distinguishes repository/staged-payload readiness from an actual registry publication and retains package/version/toolchain evidence.

Registry publication remains an external release action; repository version metadata alone is not proof that publication completed.

### PR2 — native concurrency and reopen evidence

Strengthened native Rust concurrency regression coverage with independent handles, guaranteed read/write overlap, and durability verification after concurrent mutations and reopen.

### PR3 — native-size decision evidence

Added reproducible Linux/macOS native-size evaluation before any future recorded-use/native-tree-shaking or SDK-floor decision. Evidence retains the generated `rust/Cargo.lock`, locked Cargo metadata, commit, and toolchain context.

A future tree-shaking change must satisfy both >=64 KiB absolute and >=3% relative savings under like-for-like inputs and preserve existing compatibility/correctness gates.

### PR4 — Dart isolate / FRB concurrency evidence

Added executable independent-isolate coverage through public Dart API -> FRB -> shared Rust core -> redb. Each isolate initializes and opens the same database path independently, observes the peer's committed write while both handles are active, closes successfully, and only then acknowledges completion. The parent reopens after both close acknowledgements and verifies all 64 records.

This does not make a `Box` transferable between isolates and does not create a cross-isolate watch-delivery, lock-free, fairness, or synchronization API contract.

## Merge/release gates

The 1.1 closure retains the existing full quality bar:

- format/analyze/tests;
- Flutter 3.22.0 / Dart 3.4.0 minimum compatibility;
- public/storage contract and semantic regression guards;
- native integration and durable reopen;
- encryption and migration/query/index/crash-reopen regression;
- exact `minimal | encryption | full` Rust profiles;
- FRB generated-binding reproducibility;
- native-size regression policy;
- package docs + pub dry-run;
- benchmark correctness diagnostics;
- staged Android/iOS/macOS/Linux/Windows consumers.

1.1 additionally retains the dedicated Dart isolate concurrency workflow and manual native-size evaluation workflow.

## Explicit non-changes

1.1 introduces no:

- storage-format migration or `dxtr_box/1` redesign;
- broad Dart/Rust API redesign;
- query-engine or encryption rewrite;
- new native profile;
- GPUI dependency in core;
- Tokio/runtime commitment;
- ORM/schema/model code generation;
- sync/CRDT/network database layer;
- Dart/Flutter SDK-floor increase;
- mandatory recorded-use/native tree-shaking integration.

## Post-1.1 direction

Further work should begin from observed consumer, reliability, maintenance, or interoperability needs. Platform/dev tooling, migration extensions, tree-shaking/toolchain changes, and stronger cross-isolate semantics remain separate evidence-driven decisions rather than automatic scope.
