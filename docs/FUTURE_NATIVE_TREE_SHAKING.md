# Future Native Tree Shaking

## Status

**Future optimization — do not implement yet.**

`dxtr_box` must not raise its minimum Dart or Flutter SDK solely to adopt Dart 3.13 native tree shaking at the current stage of the project.

Current compatibility target:

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

Flutter 3.22.0 ships Dart 3.4.0, so this lower bound is real and is verified by a dedicated minimum-SDK CI lane. The current stable Flutter line should continue to be tested separately.

Official references:

- https://dart.dev/tools/hooks
- https://dart.dev/blog/announcing-dart-3-13
- https://docs.flutter.dev/install/archive

## Why this matters to dxtr_box

`dxtr_box` ships a Rust native storage engine through flutter_rust_bridge/Cargokit. Normal Dart tree shaking can remove unused Dart code, but it cannot automatically infer every unused native symbol inside a bundled Rust library.

Dart 3.13 adds recorded native usage to the hook/linking model. A package link hook can use recorded usage information to determine which native APIs are referenced by the application and, where the native toolchain and symbol mapping permit it, avoid retaining unused native code.

For `dxtr_box`, the potential benefits are:

- smaller release binaries for applications that use only a subset of dxtr_box functionality;
- less native code bundled when optional features are unused;
- a better foundation for minimal CRUD, CRUD+encryption, and full-feature build profiles;
- measurable package-size improvements without deleting useful functionality from the project.

This is an optimization, not a correctness requirement. Storage durability, API semantics, migration safety, encryption, Hive functional parity, and broad Flutter compatibility have higher priority.

## Why we are not implementing it now

### 1. Preserve the minimum SDK

The package currently targets Dart 3.4 / Flutter 3.22. Making Dart 3.13-only hook APIs part of the mandatory build path would unnecessarily exclude applications on older supported Flutter releases.

Policy:

- Dart 3.4 / Flutter 3.22 remains the compatibility floor until there is an explicit versioning decision to change it;
- native tree shaking must never become a prerequisite for database correctness;
- a future implementation should be a progressive optimization where technically possible;
- supported older toolchains should continue to work, even if their native binary is larger.

### 2. Wait for the Dart 3.13 Flutter ecosystem to settle

The relevant Dart 3.13 functionality is new. Before depending on it, we need a stable Flutter toolchain carrying the required Dart behavior, sufficient FRB/Cargokit compatibility, and evidence that the hook/link workflow is reliable across all dxtr_box targets.

Do not raise the package minimum SDK just to gain this optimization.

### 3. Cargo feature splitting comes first

Tree shaking should not compensate for an unnecessarily monolithic Rust crate.

Before recorded-use native tree shaking, split optional Rust functionality into sensible Cargo features and establish reproducible build profiles. Feature splitting provides deterministic coarse-grained size control; native tree shaking can then provide finer-grained removal inside those profiles.

Required order:

```text
stable functional FRB/redb core
  -> explicit migration/recovery semantics
  -> Cargo feature splitting
  -> binary-size baselines
  -> Dart 3.13+ recorded-use/link-hook prototype
  -> compatibility + fallback validation
  -> size regression CI
  -> linker tuning if still necessary
```

### 4. FRB/native symbol mapping must be proven

`dxtr_box` uses flutter_rust_bridge-generated bindings and a Rust shared library. A future implementation must prove that:

- recorded Dart native calls can be mapped safely to the native symbols that must remain;
- FRB runtime/support symbols are retained correctly;
- callbacks, streams, allocation/free helpers, panic/error support, and indirect calls are not accidentally removed;
- Android, iOS, macOS, Linux, and Windows all produce working artifacts;
- release builds remain deterministic.

No symbol-pruning implementation should ship until this is verified with integration tests on every supported native platform.

## Future implementation gate

Revisit this work only when all of the following are true:

1. A stable Flutter toolchain containing the required Dart 3.13+ recorded-use/link-hook behavior is available and sufficiently adopted.
2. The Dart/Flutter hook API needed by dxtr_box is stable enough to depend on without making package builds fragile.
3. The existing Dart 3.4 / Flutter 3.22 compatibility floor can remain supported through a fallback, or raising it has been approved as an explicit compatibility-breaking decision.
4. Cargo feature splitting is complete enough to produce meaningful build profiles.
5. Binary-size baselines exist for at least:
   - minimal CRUD;
   - CRUD + encryption;
   - full feature set.
6. FRB/Cargokit compatibility with the hook-based build/link flow has been demonstrated.
7. A fallback path is defined and tested for supported toolchains where recorded usage is unavailable.

## Desired compatibility model

Preferred behavior:

```text
Dart 3.4+ / Flutter 3.22+ supported baseline
  -> dxtr_box works normally
  -> no mandatory recorded-use native tree shaking
  -> potentially larger native binary

Dart 3.13+ compatible Flutter/toolchain
  -> same dxtr_box API and storage semantics
  -> recorded-use/link-hook optimization enabled where safe
  -> unused native code may be removed
```

If the hook input does not provide recorded usage, the safe fallback is to retain all required native symbols rather than risk an invalid binary. That fallback must be proven before the optimization is enabled for users.

## Non-goals

This future work must not:

- change database file format;
- change CRUD or watch semantics;
- weaken encryption or durability guarantees;
- make native tree shaking mandatory for correctness;
- force a minimum-SDK increase solely for binary-size optimization;
- claim a target such as `<1 MB` without measurements for each platform, architecture, and build profile;
- use shared-runner CI measurements as if they were universally reproducible application sizes.

## Acceptance criteria for a future implementation

A future PR implementing native tree shaking should demonstrate all of the following:

- no regression in the supported minimum Flutter/Dart configuration, unless a separately approved major compatibility change explicitly raises it;
- a documented and tested fallback when recorded usage is unavailable;
- green Android, iOS, macOS, Linux, and Windows build/integration coverage;
- correctness of FRB calls, native watch streams, encryption, migration, and maintenance operations after symbol pruning;
- reproducible size measurements before and after optimization;
- separate measurements for minimal CRUD, CRUD+encryption, and full-feature builds;
- no absolute size claim without platform- and architecture-specific evidence.

Until these preconditions are met, native tree shaking remains explicitly deferred.