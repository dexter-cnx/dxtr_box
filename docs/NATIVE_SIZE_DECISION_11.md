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

1.1 PR3 adds a manual `Native Size Evaluation` workflow that runs this harness on Linux and macOS and uploads the raw TSV evidence.

The workflow is intentionally manual. Native-size evaluation is diagnostic evidence, not a new merge-blocking requirement.

## Decision rule

Do not raise the Dart or Flutter minimum, add `record_use`-dependent integration, or change native build topology only because newer tooling exists.

A future tree-shaking change requires all of the following:

1. a reproducible baseline from the existing stable integration;
2. an experimental build using the candidate SDK/tooling change;
3. the same target OS/architecture and release/profile inputs;
4. a material size reduction in the consumer-delivered native artifact or application bundle;
5. no regression in startup, CRUD, query/index, encryption, migration, or cross-platform consumer gates;
6. explicit documentation of the consumer compatibility cost of any SDK-floor increase.

## Materiality threshold

Treat changes below both of these thresholds as insufficient evidence for raising the SDK floor:

- less than 64 KiB absolute reduction; and
- less than 3% relative reduction.

These thresholds align with the existing native-size regression budget and prevent toolchain churn for noise-level savings.

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
