# Future Native Tree Shaking

## Status

**Future optimization — do not implement yet.**

`dxtr_box` must not raise its minimum Dart or Flutter SDK solely to adopt Dart 3.13 native tree shaking at the current stage of the project.

As of 2026-08-15, Dart's official documentation describes Dart 3.13 as not yet released and marks its breaking-change list as tentative. Support for link hooks and recorded-usage native tree shaking is documented as a Dart 3.13 capability.

Official references:

- https://dart.dev/tools/hooks
- https://dart.dev/resources/breaking-changes

## Why this matters to dxtr_box

`dxtr_box` ships a Rust native storage engine through flutter_rust_bridge/Cargokit. Traditional Dart tree shaking can remove unused Dart code, but it cannot automatically infer every unused native symbol inside a bundled Rust library.

Dart 3.13 introduces application-level link hooks and recorded usage information. During compilation, Dart can record the native APIs actually referenced by an application and make that information available to a package link hook through `LinkInput.recordedUses`. A link step can then preserve the native symbols that are required and remove unused native code where the toolchain and symbol mapping allow it.

For `dxtr_box`, the potential benefits are:

- smaller release binaries for applications that use only a subset of dxtr_box functionality;
- less native code bundled when optional features are unused;
- a better foundation for minimal CRUD, CRUD+encryption, and full-feature build profiles;
- measurable package-size improvements without deleting useful functionality from the project.

This is an optimization, not a correctness requirement. Storage durability, API semantics, migration safety, encryption, and Hive functional parity have higher priority.

## Why we are not implementing it now

### 1. Do not raise the minimum SDK prematurely

Making Dart 3.13-only hook APIs part of the package's required build path could force consuming applications onto a newer Dart/Flutter toolchain. A local database package should retain broad Flutter compatibility unless there is a compelling product reason to narrow it.

The current policy is therefore:

- existing supported Flutter/Dart versions must continue to build and run dxtr_box;
- native tree shaking must not become a prerequisite for correctness;
- a future implementation should behave as a progressive optimization where practical;
- older supported toolchains may bundle a larger native library rather than fail to build.

### 2. Dart 3.13 must be stable first

The Dart 3.13 APIs and integration behavior should be treated as moving until Dart 3.13 has a stable release and an appropriate stable Flutter release ships it.

Do not design the package's minimum SDK around preview or tentative behavior.

### 3. Cargo feature splitting comes first

Tree shaking should not compensate for an unnecessarily monolithic Rust crate.

Before recorded-use native tree shaking, split optional Rust functionality into sensible Cargo features and establish reproducible build profiles. Feature splitting gives deterministic coarse-grained size control; native tree shaking can then provide finer-grained removal inside those profiles.

Required order:

```text
stable functional FRB/redb core
  -> explicit migration/recovery semantics
  -> Cargo feature splitting
  -> binary-size baselines
  -> Dart 3.13+ record-use/link-hook prototype
  -> compatibility validation
  -> size regression CI
  -> linker tuning if still necessary
```

### 4. FRB/native symbol mapping must be proven

The Dart documentation describes recorded-use mapping for native APIs and notes that generated Dart method identifiers do not always map one-to-one to native symbols.

`dxtr_box` uses flutter_rust_bridge-generated bindings and a Rust shared library, so a future implementation must prove that:

- the Dart calls recorded by the compiler can be mapped safely to the native symbols that must remain;
- FRB runtime/support symbols are retained correctly;
- callbacks, streams, allocation/free helpers, panic/error support, and indirect calls are not accidentally removed;
- Android, iOS, macOS, Linux, and Windows all produce working artifacts;
- release builds remain deterministic.

No symbol-pruning implementation should ship until this is verified with integration tests on every supported native platform.

## Future implementation policy

Revisit this work only when all of the following are true:

1. Dart 3.13 or a later release containing recorded-use link hooks is stable.
2. A stable Flutter toolchain containing that Dart version is available and sufficiently adopted.
3. The current dxtr_box minimum SDK can remain supported, or there is an explicit versioning decision to raise it.
4. Cargo feature splitting is complete enough to produce meaningful build profiles.
5. Binary-size baselines exist for at least:
   - minimal CRUD;
   - CRUD + encryption;
   - full feature set.
6. FRB/Cargokit compatibility with the hook-based build/link flow has been demonstrated.
7. A fallback path is defined for supported toolchains where recorded usage is unavailable.

## Desired compatibility model

The preferred future behavior is:

```text
older supported Flutter/Dart
  -> dxtr_box works normally
  -> native tree shaking unavailable
  -> potentially larger native binary

Dart 3.13+ compatible Flutter/toolchain
  -> same dxtr_box API and semantics
  -> recorded-use/link-hook optimization enabled where safe
  -> unused native code may be removed
```

Dart's hook documentation specifies that when `LinkInput.recordedUses` is unavailable (`null`), a link hook can keep all symbols rather than tree-shake them. This is the fallback behavior we should investigate first when the feature becomes stable enough to prototype.

## Non-goals

This future work must not:

- change database file format;
- change CRUD or watch semantics;
- weaken encryption or durability guarantees;
- make native tree shaking mandatory for correctness;
- claim a target such as `<1 MB` without measurements for each platform, architecture, and build profile;
- use shared-runner CI measurements as if they were universally reproducible application sizes.

## Acceptance criteria for a future implementation

A future PR implementing native tree shaking should demonstrate all of the following:

- no regression in the supported minimum Flutter/Dart configuration;
- a documented fallback when recorded usage is unavailable;
- green Android, iOS, macOS, Linux, and Windows build/integration coverage;
- correctness of FRB calls, native watch streams, encryption, migration, and maintenance operations after symbol pruning;
- reproducible size measurements before and after optimization;
- separate measurements for minimal CRUD, CRUD+encryption, and full-feature builds;
- no absolute size claim without platform- and architecture-specific evidence.

Until these preconditions are met, native tree shaking remains explicitly deferred.