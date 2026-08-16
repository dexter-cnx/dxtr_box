# dxtr_box 0.4 published-payload consumer validation

Status: active PH-04 milestone.

## Goal

Prove that the files intended for publication are sufficient to consume and native-build `dxtr_box` without access to repository-only paths.

`dart pub publish --dry-run` remains the authoritative pub validation for metadata and the file list. PH-04 adds a complementary consumer-build gate because a dry-run does not compile an application from the staged payload.

## Staging contract

`tool/validate_published_consumer.dart` creates:

```text
build/published-payload/dxtr_box/
build/published-consumer-<platform>/
```

The payload staging pass starts from the repository root and applies the current `.pubignore` policy plus pub's hidden-file exclusion rule. It prunes ignored/hidden directories before traversal so repository metadata and build outputs cannot be copied recursively into the payload.

The current `.pubignore` intentionally uses explicit file/directory rules only. PH-04 rejects wildcard or negated rules rather than approximating gitignore semantics incorrectly. If `.pubignore` later needs richer patterns, the staging implementation must be upgraded in the same reviewed change.

Required consumer inputs include:

```text
pubspec.yaml
README.md
CHANGELOG.md
LICENSE
lib/dxtr_box.dart
rust/Cargo.toml
cargokit/
android/build.gradle
ios/dxtr_box.podspec
macos/dxtr_box.podspec
linux/CMakeLists.txt
windows/CMakeLists.txt
```

Repository-only paths such as `.github/`, `benchmark/`, `docs/`, `test/`, `tool/`, `Makefile`, `flutter_rust_bridge.yaml`, `rust/tests/`, and `rust/target/` must not appear in the staged payload.

The staged root `pubspec.yaml` must not contain a path-source dependency.

## Consumer build contract

For each supported native target, the validator creates a fresh Flutter application and makes it depend only on:

```yaml
dxtr_box:
  path: ../published-payload/dxtr_box
```

The generated application imports the public `package:dxtr_box/dxtr_box.dart` library so both the Dart API and Flutter plugin registration participate in compilation.

The build gates are:

```text
Android  flutter build apk --debug
iOS      flutter build ios --debug --no-codesign
macOS    flutter build macos --debug
Linux    flutter build linux --debug
Windows  flutter build windows --debug
```

A pass proves that native Cargokit/Rust build inputs required by that platform are reachable from the staged package boundary.

## CI policy

`Platform Builds` is the PH-04 consumer gate for all five native targets. Changes to `.pubignore` or the staging validator trigger the workflow in addition to ordinary Dart/Rust/platform source changes.

The source `example/` remains useful documentation and is still covered by normal repository analysis/tests and local Make targets, but platform release evidence is now based on isolated staged consumers because that more closely represents pub.dev consumption.

## Interpretation

- missing consumer input: hard failure;
- repository-only payload leakage: hard failure;
- path dependency in the publishable root package: hard failure;
- staged consumer dependency resolution failure: hard failure;
- native build failure on any supported platform: hard failure;
- no package is uploaded by this validation.

PH-04 does not claim byte-for-byte equivalence with pub.dev's server-side archive. `dart pub publish --dry-run` remains mandatory alongside this gate and is the source of truth for pub validation/file listing.

## Non-goals

PH-04 does not change storage, query/index, encryption, migration, FRB API semantics, native profiles, SDK floors, or performance policy.
