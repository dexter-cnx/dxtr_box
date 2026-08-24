# Dxtr_Box 1.0 Release Readiness Audit

## Goal

Prepare Dxtr_Box for a future stable `1.0.0` release without declaring stability before the public contracts are explicitly frozen and defended by CI.

0.10 closed real-world workload evidence. 1.0 work is stabilization and release-contract work, not another feature milestone.

## Current release candidate baseline

```text
Flutter package/plugin: dxtr_box
Rust crate/native lib:  rust_lib_dxtr_box
Current package version: 0.10.0-dev.1
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          dxtr_box/1
native profiles:         minimal | encryption | full
```

The stable release must not silently change these identities while moving from the pre-1.0 series to `1.0.0`.

## 1.0 contract freeze candidates

### Dart package boundary

The stable Dart entrypoint remains `package:dxtr_box/dxtr_box.dart` and exports the box API, events, `BoxStore`, deprecated `DxtrBox` compatibility shim, Hive CE migration helpers, query AST/builder, and `BoxField<T>` metadata.

### Rust crate boundary

The native Rust crate remains `rust_lib_dxtr_box` and produces `cdylib`, `staticlib`, and `rlib` artifacts. Root native exports remain centered on `DxtrBoxError`, `DxtrBox`, `BoxHandle`, `IndexDefinition`, `Record`, and full-profile query types.

`api::*` remains the FRB-facing compatibility surface. The Rust frontend must continue to call the shared Rust core directly and must not acquire a Dart/FRB dependency direction.

### Durable storage boundary

The stable storage identity remains:

```text
meta[format_version] = dxtr_box/1
```

A future storage-format change requires explicit compatibility/migration behavior and must not be smuggled into a dependency or refactor PR.

### Native profile boundary

The supported consumer profiles remain exactly:

```text
minimal
minimal + encryption
full (default)
```

Internal Cargo features may compose those profiles, but no fourth supported profile is introduced for 1.0.

## Release blockers before `1.0.0`

1. Public package/native identity guard must run in the existing contract gate.
2. Dart and Rust conformance suites must remain green across the supported profiles.
3. Staged published-payload consumers must remain green on Android, iOS, macOS, Linux, and Windows.
4. Package dry-run, generated API docs, FRB reproducibility, native-size regression, migration/query/index/crash-reopen regression, minimum SDK validation, and 0.10 workload evidence must remain green.
5. README, CHANGELOG, code walkthrough, handoff, and a final 1.0 release audit must agree on the stable contract.
6. `1.0.0` is bumped only in the final closure PR after all prior 1.0 stabilization PRs are merged.

## Proposed 1.0 sequence

```text
PR1 — contract-freeze audit + stronger package/native/storage identity guard
PR2 — public API semantic regression inventory + missing compatibility tests
PR3 — release-candidate published-consumer / migration / upgrade evidence
PR4 — final release audit, docs sync, version 1.0.0 closure
```

New product features are deferred until after the stable contract is closed.

## Explicit non-goals

1.0 readiness does not add GPUI integration inside the core package, ORM/schema generation, networking/replication, Tokio commitment, storage-format redesign, query/encryption rewrites, a fourth supported native profile, or broad Dart API renaming.

## PR1 acceptance

- [ ] package name, native library/crate identity, SDK floors, FRB/redb pins, and crate types are guarded;
- [ ] Dart entrypoint export boundary remains guarded;
- [ ] Rust root native export boundary is guarded exactly, including unexpected additions;
- [ ] Cargo `[package]` and `[lib]` names are checked independently;
- [ ] `dxtr_box/1` marker and metadata key remain guarded;
- [ ] existing `make contract-check` exercises the stronger guard;
- [ ] full CI passes before merge.

No 1.0 stability claim is made by PR1 alone.
