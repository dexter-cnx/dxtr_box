# Native Size Regression Policy — 0.4

Status: active production-hardening gate.

## Purpose

0.3 established two prerequisites before any cross-commit budget was safe to enforce:

1. stable product-relevant native profiles (`minimal`, `encryption`, `full`);
2. same-commit reproducibility for release-library byte measurements.

0.4 turns that measurement system into a controlled regression gate. The goal is to catch accidental native binary growth without treating every byte increase as a product failure.

## Comparison model

The gate compares the pull-request base commit with the candidate head commit **inside the same CI job**:

```text
same runner
same OS / architecture
same rustc + cargo toolchain
same measurement script
base SHA build -> exact bytes
head SHA build -> exact bytes
```

CI uses a full checkout history so the base SHA is available locally. The harness creates a detached Git worktree for the base commit and builds base/head into separate target directories.

This deliberately avoids comparing against historical workflow artifacts, because historical runner/toolchain differences could be mistaken for source-code growth.

## Profiles

Every comparison covers exactly the three public native product profiles:

```text
minimal
  --no-default-features

encryption
  --no-default-features --features encryption

full
  default features
```

The gate must not introduce a fourth product profile.

## Default growth budget

For each profile, allowed positive growth is:

```text
max(65,536 bytes, 3% of the base artifact)
```

A profile fails only when:

```text
head_bytes - base_bytes > allowed_growth_bytes
```

Shrinks always pass. Growth at or below the allowance passes.

Why a hybrid allowance:

- the absolute floor avoids overreacting to small fixed-size changes;
- the percentage component scales if artifacts become materially larger later;
- the current ~2 MB Linux x64 artifacts therefore have an effective allowance close to 64 KiB.

This is a regression budget, not a target size and not permission to spend the allowance routinely.

## Intentional growth

Do not bypass the gate for an intentional feature. Instead:

1. explain the product/technical reason in the PR;
2. record the measured per-profile delta;
3. decide explicitly whether the feature justifies the increase;
4. change the policy only in a reviewed commit if the long-term budget itself is no longer appropriate.

Environment overrides exist for controlled experiments/local validation, but CI pins the 0.4 policy values explicitly.

## Commands

Default local comparison against the parent commit:

```text
make native-size-regression
```

Compare against another ref:

```text
make native-size-regression SIZE_BASE_REF=origin/main
```

Override budgets for diagnosis only:

```text
make native-size-regression \
  SIZE_MAX_GROWTH_BYTES=131072 \
  SIZE_MAX_GROWTH_PERCENT=5
```

The harness writes:

```text
build/native-size-regression/native-size-regression.tsv
```

with base/head SHAs, toolchain/platform metadata, per-profile byte counts, deltas, effective allowance, growth percentage, and pass/fail status.

## CI contract

The Linux x64 native-size job now has three separate responsibilities:

1. record current absolute profile sizes;
2. verify same-commit reproducibility across repeated builds;
3. compare base vs head and enforce the controlled growth budget.

The artifact contains all three machine-readable TSV files.

## Non-goals

This 0.4 slice does not:

- change Rust features or runtime behavior;
- change storage format or FRB shape;
- raise Flutter/Dart minimum versions;
- use Dart 3.13 recorded-use/native tree shaking;
- establish Android/iOS final application-size budgets;
- claim shared-runner benchmark timing stability.

Application bundle/APK/IPA size policy, if needed, is a separate production-hardening decision because linker/packaging behavior differs from the host release dynamic-library measurement used here.
