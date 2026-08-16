# dxtr_box 0.4 package / publication hardening

Status: PH-02 complete; PH-04 published-payload consumer validation active.

## Goal

Make the repository layout and CI prove that the package a Flutter application receives from pub.dev is self-contained and buildable without repository-relative path dependencies.

## Package topology

`dxtr_box` is the single public Flutter package and FFI plugin:

```text
dxtr_box/
  lib/                 Dart public API + generated FRB bindings
  rust/                Rust crate (`rust_lib_dxtr_box`)
  cargokit/            vendored native build integration
  android/
  ios/
  macos/
  linux/
  windows/
  example/
  pubspec.yaml
  README.md
  CHANGELOG.md
  LICENSE
```

The Flutter package name is `dxtr_box`. The native Rust crate/library name remains `rust_lib_dxtr_box` so generated FRB loading and native artifacts retain their existing identity.

The previous `rust_builder/` helper package is removed. There is no runtime or build dependency using `path:` from the root `pubspec.yaml`.

## Platform build mapping

```text
Android  android/build.gradle
  -> ../cargokit
  -> ../rust

iOS/macOS  {ios,macos}/dxtr_box.podspec
  -> ../cargokit/build_pod.sh
  -> ../rust

Linux/Windows  {linux,windows}/CMakeLists.txt
  -> ../cargokit/cmake/cargokit.cmake
  -> ../rust
```

Cargokit builds the native library `rust_lib_dxtr_box`; the Flutter plugin target/package remains `dxtr_box`.

## Publication gates

`make package-readiness` runs:

```text
flutter pub get
dart doc --output build/doc
dart pub publish --dry-run --ignore-warnings
```

CI additionally asserts:

- `rust_builder/` is absent;
- the Rust crate, Cargokit, and all five platform build integrations are present at package root;
- root publishable dependencies do not use `path:` sources.

The exact FRB 2.8.0 dependency remains intentional because runtime, codegen, macros, and checked-in bindings must stay version-aligned. Pub's broad-constraint advisory is therefore ignored during the dry-run while validation errors remain fatal.

## Published payload

`.pubignore` excludes repository-only CI, benchmark, internal test, and development tooling. The package must retain the files required by consumers:

- `lib/`;
- `rust/` production crate sources;
- `cargokit/`;
- Android/iOS/macOS/Linux/Windows plugin build files;
- README / CHANGELOG / LICENSE;
- source example.

Do not exclude a native build input merely to reduce archive size. Package correctness has priority over cosmetic package-size reduction.

## PH-04 staged-consumer validation

A successful pub dry-run validates metadata and reports intended files, but it does not compile an application from the publication boundary. PH-04 closes that evidence gap with:

```text
tool/validate_published_consumer.dart
  -> stage payload using current .pubignore policy
  -> reject missing required native inputs
  -> reject repository-only leakage
  -> reject root path-source dependencies
  -> create fresh Flutter consumer
  -> depend only on staged dxtr_box copy
  -> import public Dart API
  -> build target platform
```

`Platform Builds` executes this isolated staged-consumer flow for Android, iOS, macOS, Linux, and Windows. This replaces source-checkout example builds as the release-facing platform proof. The checked-in example remains documentation and retains local Make targets.

The staging helper deliberately supports the current explicit file/directory `.pubignore` rules only. Wildcards or negation fail closed until exact support is added, avoiding silent divergence from pub ignore semantics.

See `docs/PUBLISHED_PAYLOAD_CONSUMER_04.md`.

## Version policy

The active package preview is `0.4.0-dev.1`. Publication is a separate explicit release action; hardening PRs do not upload anything to pub.dev.

Before an actual release:

1. require CI and all staged Platform Builds green on the release candidate;
2. inspect `dart pub publish --dry-run` output for the exact archive file list and warnings;
3. confirm CHANGELOG and README match the release version;
4. verify API docs generate without errors;
5. verify native-size policy passes;
6. publish only from a clean, reviewed commit/tag.

## Non-goals

PH-02/PH-04 do not change:

- storage format;
- FRB API shape;
- query/index semantics;
- encryption semantics;
- Hive CE migration behavior;
- the three Rust capability profiles (`minimal`, `encryption`, `full`);
- Dart >=3.4 / Flutter >=3.22 minimum compatibility.
