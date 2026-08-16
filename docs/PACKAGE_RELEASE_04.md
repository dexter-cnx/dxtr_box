# dxtr_box 0.4 package / publication hardening

Status: active PH-02 milestone.

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
dart pub publish --dry-run
```

CI additionally asserts:

- `rust_builder/` is absent;
- the Rust crate, Cargokit, and all five platform build integrations are present at package root;
- root publishable dependencies do not use `path:` sources.

The normal CI and Platform Builds remain mandatory because a successful pub dry-run validates package metadata/archive shape but does not prove every native platform build.

## Published payload

`.pubignore` excludes repository-only CI, benchmark, internal test, and development tooling. The package must retain the files required by consumers:

- `lib/`;
- `rust/` production crate sources;
- `cargokit/`;
- Android/iOS/macOS/Linux/Windows plugin build files;
- README / CHANGELOG / LICENSE;
- source example.

Do not exclude a native build input merely to reduce archive size. Package correctness has priority over cosmetic package-size reduction.

## Version policy

The active package preview is `0.4.0-dev.1`. Publication is a separate explicit release action; merging PH-02 does not upload anything to pub.dev.

Before an actual release:

1. require CI and Platform Builds green on the release candidate;
2. inspect `dart pub publish --dry-run` output for the exact archive file list and warnings;
3. confirm CHANGELOG and README match the release version;
4. verify API docs generate without errors;
5. verify native-size policy passes;
6. publish only from a clean, reviewed commit/tag.

## Non-goals

PH-02 does not change:

- storage format;
- FRB API shape;
- query/index semantics;
- encryption semantics;
- Hive CE migration behavior;
- the three Rust capability profiles (`minimal`, `encryption`, `full`);
- Dart >=3.4 / Flutter >=3.22 minimum compatibility.
