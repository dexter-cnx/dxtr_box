# Change-aware CI strategy

This document defines the CI topology introduced after 0.4 production hardening. It changes validation scheduling only; it does not change `dxtr_box` runtime, storage, encryption, query/index, migration, or 0.5 read-path semantics.

## Hard contracts

CI optimization must preserve:

- Dart >= 3.4 and Flutter >= 3.22;
- Flutter package identity `dxtr_box`;
- Rust crate/native identity `rust_lib_dxtr_box`;
- exactly three native capability profiles: `minimal`, `encryption`, `full`;
- durable metadata `format_version = dxtr_box/1`;
- exact `flutter_rust_bridge` / codegen 2.8.0 alignment;
- authoritative native `get` and `containsKey` reads;
- encryption authentication and durability;
- migration, query/index, cross-process, reopen, package, publication, and platform compatibility;
- native-size growth budget `max(65,536 bytes, 3% of base artifact)`.

## DAG

```text
change-detection
      |
      v
   Fast CI
      |
      +--> minimum SDK
      +--> full Dart tests
      +--> three Rust profiles
      |       +--> macOS/Windows platform compilation
      +--> native integration
      +--> storage/migration/query regression
      +--> FRB drift validation
      +--> package/publication readiness
      +--> native-size policy
      +--> five-platform staged consumers
      +--> benchmark correctness/diagnostic smoke
                  |
                  v
        Merge Gate / full quality bar
```

Expensive jobs do not start until Fast CI succeeds. Generic Dart formatting, rustfmt, analysis, and Rust linting are performed on Ubuntu in Fast CI rather than duplicated across operating systems.

## Central change detection

`.github/workflows/ci.yml` owns one `change-detection` job using centralized path filters. The primary domains are:

1. `docs`
2. `dart_core`
3. `rust_core`
4. `encryption`
5. `ffi`
6. `durable_storage`
7. `packaging`
8. `platform`
9. `native_size`
10. `benchmark`
11. `ci`

Additional outputs distinguish public API changes and individual platform directories so policy can be made more precise without introducing separate workflow-level path filters.

A job skipped by a false affected-condition is intentionally `skipped`; it is not a missing workflow status. The stable terminal check is `Merge Gate / full quality bar`.

## Fast CI and local preflight

Every PR commit runs Fast CI first:

```text
make format-check
make rust-check
make analyze
make test-fast
make ci-fast
make preflight
```

`make ci-fast` and `make preflight` cover Dart formatting, rustfmt, Flutter analyze, Rust clippy, compile checks for exactly the three supported feature profiles, cheap Rust unit tests, cheap Dart unit/contract tests, and the public/storage contract verifier.

A rustfmt failure therefore fails before macOS/Windows/platform/native-size/benchmark jobs are allowed to start.

## Affected CI policy

Draft pull requests use Fast CI plus affected expensive jobs. This is the iteration mode.

Examples:

| Change | Expected expensive work after Fast CI |
| --- | --- |
| rustfmt-only correction | none unless another affected domain changed |
| docs-only | none |
| Dart-only internal | full Dart tests + minimum SDK; no FRB/native-size/platform matrix |
| internal Rust | three profiles + native integration + native-size + cross-platform native compilation/platform consumers when production native artifact is affected |
| encryption | encryption/profile tests + native integration + storage/migration + native-size + affected platform validation |
| FFI API | FRB drift + native integration + profile/platform validation |
| durable storage/migration | storage/migration/query/reopen compatibility + native integration + profiles + native-size |
| Cargo/native dependency | profiles + native-size + platform consumer validation |
| benchmark-only | benchmark correctness/diagnostic smoke only |
| platform-only | affected/common platform validation; Fast CI still precedes it |

Correctness gates remain stronger than timing diagnostics. Shared-runner benchmark timing is evidence, not an arbitrary performance threshold.

## Full merge validation

A pull request in Draft state cannot be merged and may use affected CI for rapid iteration. Changing it to Ready for review emits a `ready_for_review` event and switches `full_validation=true`. Every subsequent commit on a non-draft PR also runs full validation.

Full mode requires success for:

- Fast CI;
- minimum Flutter 3.22 / Dart 3.4 compatibility;
- full Dart tests;
- exactly three Rust profiles;
- macOS and Windows Rust platform compilation in addition to Ubuntu profile tests;
- native integration;
- migration/storage/query/index/reopen correctness;
- FRB generated-binding drift;
- package docs/publication dry-run;
- native-size regression policy;
- Android/iOS/macOS/Linux/Windows staged published consumers;
- benchmark harness correctness and diagnostic smoke.

`Merge Gate / full quality bar` fails if any full-mode job is skipped, cancelled, or failed. Branch protection should require this stable check rather than individual affected jobs. This avoids permanently Pending required checks while still preventing selective Draft CI from becoming merge evidence.

## Native-size trigger policy

Native-size runs when native production source, Cargo manifests/locks, native build/link/package integration, or native-size tooling can affect the artifact. It does not run for docs-only or ordinary Dart-only work.

The policy remains:

```text
allowed_growth = max(65,536 bytes, 3% of base artifact)
```

## FRB trigger policy

FRB drift validation runs for exported Rust API changes, Dart native adapter/generated binding changes, FRB configuration, or full merge validation. Internal Rust, docs-only, and benchmark-only Draft iteration does not reinstall/regenerate FRB unnecessarily.

`flutter_rust_bridge_codegen` remains exactly 2.8.0. CI caches the versioned codegen binary only; it does not cache generated native artifacts in a way that could conceal ABI/profile drift.

The separate `FRB Probe` workflow is manual diagnostic tooling only.

## Platform trigger policy

Five-platform staged consumer validation remains available and is mandatory in full validation. Draft affected CI gates common plugin/native/package changes and platform-specific changes only after Fast CI.

The old independently-triggered `Platform Builds` workflow is folded into the main DAG so expensive consumers cannot start before cheap failures are known.

## Benchmark trigger policy

Benchmark jobs run for benchmark source/workflow changes, read-path production code that the benchmark exercises, durable-storage/read semantics, explicit dispatch, and full validation. Correctness failures remain blocking. Timing values remain diagnostic and machine-readable artifacts continue to upload.

## Concurrency

CI uses one per-PR/ref concurrency group with `cancel-in-progress: true`. A newer commit cancels obsolete work for the same PR. Full validation is not a separate narrower workflow, so a diagnostic run cannot replace the stable full merge status.

## Branch-protection migration

After this CI change lands, update the protected `main` branch required status checks to require:

```text
CI / Merge Gate / full quality bar
```

Remove requirements that refer to deleted standalone `Platform Builds` job names. Individual affected jobs should remain visible evidence but should not themselves be required statuses, because intentionally skipped affected jobs are represented through the terminal merge gate.
