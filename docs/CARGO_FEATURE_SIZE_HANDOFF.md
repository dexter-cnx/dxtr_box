# Cargo feature splitting and native size handoff

Status: active milestone after PR #11.

## Product profiles

| Profile | Cargo invocation | Contract |
| --- | --- | --- |
| minimal | `--no-default-features` | CRUD + lifecycle + native watch |
| encryption | `--no-default-features --features encryption` | minimal + encrypted create/open/read/write |
| full | default features | encryption + maintenance (`compact`, plaintext -> encrypted migration) |

`full` remains the default to preserve current Flutter/Cargokit behavior.

## Why watch stays in minimal

`DxtrBox.open()` currently registers a native watcher before metadata hydration. Removing watch from the native core would make the normal public Box lifecycle unusable, so watch is not an optional Cargo feature in this milestone.

## Reduced-profile behavior

Public FRB symbols stay stable across profiles. Optional operations fail explicitly:

- `compact()` requires `maintenance`;
- plaintext -> encrypted migration requires `encryption` + `maintenance`;
- encrypted create/open requires `encryption`.

No reduced profile may silently no-op an unsupported operation.

## Validation

Rust CI must run on Ubuntu, macOS, and Windows for:

1. minimal profile;
2. encryption profile;
3. full profile.

The normal Dart/Flutter integration lane continues to build the default `full` profile.

## Binary-size baseline

`tool/native_size_baseline.sh` builds all three profiles in isolated target directories and records exact dynamic-library bytes plus git/toolchain/platform metadata.

Run locally with:

```text
make native-size-baseline
```

CI initially records Linux x86_64 in one same-run comparison and uploads `build/native-size` as an artifact. There is intentionally no size regression threshold yet.

## Acceptance gate

This milestone is complete when:

- all three product profiles compile and test on the Rust host matrix;
- default/full preserves current production behavior;
- reduced maintenance calls fail explicitly;
- Linux x86_64 size results are captured from CI for all profiles;
- README, PROJECT_HANDOFF, CODE_WALKTHROUGH, and TESTING document profile behavior and the measured baseline;
- no Dart/Flutter minimum SDK increase is introduced;
- Dart 3.13 recorded-use/native tree shaking remains deferred.
