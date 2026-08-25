# dxtr_box 1.2 Planning Baseline

## Purpose

1.2 starts only from observed needs. The 1.1 milestone closed reliability/concurrency evidence without changing the stable API or durable format. This document is a decision framework, not a commitment to add features.

## Stable baseline

```text
package:                 dxtr_box 1.1.0
Rust crate/native lib:   rust_lib_dxtr_box
Dart:                    >= 3.4.0 < 4.0.0
Flutter:                 >= 3.22.0
flutter_rust_bridge:     2.8.0 exactly
redb:                    2.1.0
durable format:          dxtr_box/1
native profiles:         minimal | encryption | full
```

## First gate: hosted release verification

Repository version `1.1.0` is not proof that a hosted package exists. After publication, run `Registry Consumer Verification` for `1.1.0` and require hosted resolution plus Android, iOS, macOS, Linux, and Windows consumer builds before describing the hosted release as verified.

Do not fabricate registry evidence and do not make repository CI depend on a package that has not been published yet.

## Candidate buckets

### A. Developer inspection tooling

Consider only if real consumers need to inspect local `.dxtr` data during development. Prefer a separate read-only tool/frontend over coupling UI dependencies into the core package.

Before implementation, document:

- target workflow and user;
- read-only vs mutation requirements;
- encryption-key handling;
- whether the tool can consume the native Rust frontend directly;
- maintenance and platform cost.

### B. Migration / interoperability

Extend migration only for a concrete source/edge case. Preserve destination reservation, atomicity, encryption behavior, reopen durability, and existing `dxtr_box/1` files.

Hive CE remains one optional migration source, not a compatibility target to imitate broadly.

### C. Native-size / recorded-use experiment

The 1.1 native-size baseline exists specifically to stop speculative SDK-floor changes. A Dart 3.13 recorded-use/native-tree-shaking experiment is eligible only if it is measured against retained like-for-like baselines.

A candidate must clear both:

- >= 64 KiB absolute reduction; and
- >= 3% relative reduction

for a relevant artifact, while retaining all correctness and platform gates. A measurement that does not clear the threshold is evidence to keep current SDK floors and build topology.

### D. Stronger isolate/watch/order semantics

1.1 proves independent isolates can init/open the same path, observe committed writes, close successfully, and reopen durably. Do not expand that into cross-isolate `Box` transfer, watch fan-out, fairness, or ordering guarantees without a consumer case and executable failure/ordering tests.

### E. Web strategy

Web is not a checkbox feature. Because the authoritative engine is Rust/redb and current packaging is native FFI, any Web path must first decide whether it is:

- unsupported by design;
- a separate frontend with different storage semantics; or
- a future WASM/storage architecture project.

Do not silently introduce a second durable contract under the same API.

## Explicit non-goals

Do not add for 1.2 without a separately justified architecture decision:

- GPUI in core;
- Tokio/runtime commitment;
- ORM/schema/model generation;
- sync/CRDT/network database behavior;
- a fourth native profile;
- storage-format redesign;
- query/encryption rewrite;
- Hive parity for its own sake.

## Proposed sequence

```text
PR1 1.2 planning baseline / post-1.1 handoff
PR2 investigation or executable evidence for one observed need only
PR3 implementation only if PR2 evidence justifies a change
PR4 closure audit/docs/version only if a real 1.2 scope exists
```

PR2-PR4 are conditional. It is valid for 1.2 to remain planning-only until a real consumer need appears.

## Decision rule

A runtime/tooling change must:

1. solve a concrete user, reliability, maintenance, or interoperability problem;
2. preserve the stable public API and `dxtr_box/1`, or explicitly version/migrate the change;
3. include executable evidence and failure cases;
4. preserve existing CI, SDK-floor, profile, migration, encryption, native-size, and five-platform package gates;
5. be smaller and safer than introducing a parallel storage/runtime architecture where possible.
