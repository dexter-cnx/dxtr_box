# dxtr_box 1.1 Planning Baseline

## Purpose

1.1 is the first post-1.0 milestone. It must preserve the stable 1.0 public/storage contract unless a change is explicitly justified, versioned, and migrated.

This document is a planning baseline, not a feature commitment.

## 1.0 baseline that must remain protected

```text
package:                 dxtr_box 1.0.0
Rust crate/native lib:   rust_lib_dxtr_box
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          dxtr_box/1
native profiles:         minimal | encryption | full
```

Compatibility-sensitive surfaces include the Dart export boundary, Rust root API, query/index semantics, encryption behavior, migration behavior, native profile identities, package/plugin topology, and existing `.dxtr` files.

## First post-release verification

Before starting a new runtime feature, verify the release as an external consumer rather than relying only on the repository state:

1. confirm the intended `1.0.0` package is actually available from the target package registry before describing it as published;
2. resolve a clean generated consumer against the registry package rather than a local/path payload;
3. build representative Android, iOS, macOS, Linux, and Windows consumers from that resolved package;
4. retain package/version/toolchain evidence;
5. keep repository CI and contract guards unchanged unless evidence identifies a real release defect.

A repository merge to version `1.0.0` is not by itself proof that the registry publication completed.

## Evidence-backed 1.1 candidate buckets

### A. Reliability / concurrency evidence — highest priority candidate

The historical Hive compatibility inventory flags isolate/concurrency behavior as a reliability candidate. 1.1 may add explicit multi-isolate or equivalent process/runtime-boundary validation if the current Dart/FRB architecture can support a meaningful test without changing the storage contract.

Acceptance should focus on correctness, visibility, lifecycle, and failure behavior—not API imitation of Hive.

### B. SDK / native tree-shaking evaluation — investigation only

Dart 3.13 recorded-use/native tree shaking was intentionally deferred before 1.0. Re-evaluate only if measurable package/native-size or deployment evidence justifies changing the SDK floor or build integration.

Do not raise the Dart/Flutter minimum merely to adopt a language/tooling feature without quantified benefit and consumer impact evidence.

### C. Platform/tooling decisions — evidence before implementation

Potential future areas already present in the compatibility inventory include Web strategy and database inspection/dev tooling. Neither is automatically a 1.1 requirement.

For each candidate, first document:

- concrete consumer use case;
- architecture impact;
- compatibility impact;
- binary/build impact;
- maintenance cost;
- whether it requires a new frontend rather than a core change.

### D. Migration/interoperability hardening — use-case driven

Hive CE remains an optional migration source, not the product identity. Any additional migration behavior must come from a concrete migration case and must preserve the existing destination-safety and durability guarantees.

## Explicit non-goals for 1.1 planning

Do not use 1.1 as a reason to add:

- GPUI into the core package;
- Tokio/runtime dependency commitments;
- ORM/schema/model code generation;
- cloud sync/CRDT/network database behavior;
- a fourth native profile;
- a storage-format redesign without a migration plan;
- a broad query/encryption rewrite;
- Hive feature parity for its own sake.

## Proposed sequence

```text
PR1 post-release registry/external-consumer verification evidence
PR2 reliability/concurrency investigation and tests, only if evidence justifies it
PR3 one separately approved 1.1 improvement, selected from measured needs
PR4 1.1 closure audit/docs/version only after the selected scope is complete
```

PR2-PR4 are intentionally conditional. If post-release evidence does not justify runtime changes, 1.1 should remain small rather than manufacture scope.

## Decision rule

A 1.1 change should pass all of these tests:

1. solves an observed consumer/reliability/maintenance problem;
2. remains backward compatible with the 1.0 public API and `dxtr_box/1`, or explicitly documents why a versioned compatibility decision is required;
3. has executable evidence, not only a design preference;
4. does not weaken existing CI, package, native-size, migration, encryption, or cross-platform gates.
