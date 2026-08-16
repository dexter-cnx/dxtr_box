# Cargo feature splitting and native size handoff

Status: profile split completed in 0.3; cross-commit size policy continues in 0.4.

## Product profiles

| Profile | Cargo invocation | Contract |
| --- | --- | --- |
| minimal | `--no-default-features` | CRUD + lifecycle + native watch |
| encryption | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| full | default features | encryption + maintenance + query/index implementation |

`full` remains the default to preserve current Flutter/Cargokit behavior.

## Why watch stays in minimal

`DxtrBox.open()` currently registers a native watcher before metadata hydration. Removing watch from the native core would make the normal public Box lifecycle unusable, so watch is not an optional Cargo feature.

## Reduced-profile behavior

Public FRB symbols stay stable across profiles. Optional operations fail explicitly rather than silently no-oping. Boxes containing persisted indexes require `full` because reduced profiles cannot safely maintain derived index state.

## Validation

Rust CI runs on Ubuntu, macOS, and Windows for:

1. minimal profile;
2. encryption profile;
3. full profile.

The normal Dart/Flutter integration lane continues to build the default `full` profile.

## Binary-size measurement history

`tool/native_size_baseline.sh` builds all three profiles in isolated target directories and records exact dynamic-library bytes plus git/toolchain/platform metadata.

PR #12 established the first Linux x86_64 profile baseline. PR #13 added repeated same-commit builds and made zero-spread reproducibility the prerequisite for any cross-commit budget.

Run the measurement/reproducibility tools locally with:

```text
make native-size-baseline
make native-size-stability
```

## 0.4 cross-commit policy

0.4 adds `tool/native_size_regression.sh` and `make native-size-regression`.

The gate builds the base SHA and head SHA on the same runner/toolchain and compares each of the three profiles. Default allowed positive growth per profile is:

```text
max(65,536 bytes, 3% of the base artifact)
```

This avoids using historical artifacts whose runner/toolchain may differ from the current build. CI pins the policy values and uploads the comparison TSV together with the absolute and same-commit stability measurements.

See `docs/NATIVE_SIZE_POLICY_04.md` for the normative 0.4 contract.

## Preserved constraints

- exactly three public native profiles;
- no Dart/Flutter minimum SDK increase caused by size tooling;
- Dart 3.13 recorded-use/native tree shaking remains deferred;
- binary-size policy must not weaken correctness, encryption, durability, or query/index invariants;
- intentional growth must be documented and reviewed rather than hidden by bypassing the gate.
