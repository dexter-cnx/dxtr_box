# dxtr_box 1.1 Native-size / Tree-shaking Decision Evidence

## Purpose

This document defines the evidence required before changing the stable SDK floor or build integration to pursue Dart/native tree shaking.

The current stable contract remains unchanged:

```text
package:               dxtr_box 1.0.0
Dart:                  >= 3.4.0 < 4.0.0
Flutter:               >= 3.22.0
flutter_rust_bridge:   2.8.0 exactly
redb:                  2.1.0
durable format:        dxtr_box/1
native profiles:       minimal | encryption | full
```

## Measurement baseline

The repository already has `tool/native_size_baseline.sh`, which builds the exact native profiles and records artifact bytes with git, OS, architecture, rustc, and cargo metadata.

1.1 PR3 adds a manual `Native Size Evaluation` workflow that runs this harness on Linux and macOS and uploads the raw TSV evidence together with the generated `Cargo.lock` and locked Cargo metadata. Historical comparisons therefore retain the exact dependency resolution as well as the commit and toolchain context.

The workflow is intentionally manual. Native-size evaluation is diagnostic evidence, not a new merge-blocking requirement.

## Decision rule

Do not raise the Dart or Flutter minimum, add `record_use`-dependent integration, or change native build topology only because newer tooling exists.

A future tree-shaking change requires all of the following:

1. a reproducible baseline from the existing stable integration;
2. an experimental build using the candidate SDK/tooling change;
3. the same target OS/architecture, dependency resolution, and release/profile inputs;
4. a material size reduction in the consumer-delivered native artifact or application bundle;
5. no regression in startup, CRUD, query/index, encryption, migration, or cross-platform consumer gates;
6. explicit documentation of the consumer compatibility cost of any SDK-floor increase.

## Materiality threshold

A reduction must clear the larger effective threshold before it can be used as evidence for raising the SDK floor:

- at least 64 KiB absolute reduction; **and**
- at least 3% relative reduction.

Equivalently, the required reduction is `max(64 KiB, 3% of the baseline artifact)`.

This aligns with the existing native-size regression budget and prevents toolchain churn for noise-level savings. A reduction that meets only one threshold is not material enough for an SDK-floor or build-topology change.

A larger reduction is still not automatic approval. The compatibility cost must be evaluated separately.

## Profile interpretation

Measure all three profiles independently:

- `minimal` — core CRUD/lifecycle/watch only;
- `encryption` — minimal plus encrypted open/create;
- `full` — default profile including query/index support.

A technique that reduces only one profile must not be generalized to the others without evidence.

## Current decision

PR3 does not enable tree shaking and does not raise SDK floors. It only makes the size evidence reproducible across Linux and macOS so a later decision can compare like-for-like measurements.

Until an experimental candidate demonstrates material benefit under the rules above, the existing SDK and native integration remain preferred.
