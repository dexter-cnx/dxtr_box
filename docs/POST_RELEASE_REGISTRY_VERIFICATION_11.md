# dxtr_box 1.1 PR1 — Registry-resolved consumer verification

## Purpose

The repository reaching `version: 1.0.0` is not proof that the package is available from the hosted registry. This verification deliberately resolves a clean Flutter consumer from the registry rather than from the repository or a staged path dependency.

## Current publication state

At the time this PR was prepared, a public pub.dev search did not return `dxtr_box`. Therefore the project must not describe `1.0.0` as registry-published until the hosted package can be resolved successfully.

This PR adds verification infrastructure only. It does not publish the package and does not make registry availability a normal merge-blocking CI requirement before publication.

## Verification command

After `dxtr_box 1.0.0` is published, run the manual GitHub Actions workflow:

```text
Registry Consumer Verification
version = 1.0.0
```

The workflow runs one clean generated consumer for each supported platform:

```text
Android
Linux
iOS
macOS
Windows
```

Each consumer executes:

1. `flutter create` for the target platform;
2. `flutter pub add dxtr_box:<version>` with no path or git override;
3. package-config validation proving `dxtr_box` resolved from a hosted cache and at the requested exact version;
4. compilation against representative stable public surfaces (`BoxStore`, deprecated `DxtrBox` compatibility shim, query builder/model, `IndexDefinition`, and Hive CE migration entry point);
5. target-platform debug build;
6. upload of JSON evidence containing package, version, hosted package root, platform, and Flutter toolchain metadata.

## Evidence contract

A platform passes only when all of the following are true:

- the requested package version resolves from the hosted registry;
- package resolution is not a local/path checkout;
- representative public API references compile;
- the target platform build succeeds;
- evidence JSON is retained as a workflow artifact.

All five platforms must pass before recording the registry release as externally verified.

## Compatibility boundary

This work does not change:

```text
package version = 1.0.0
durable format = dxtr_box/1
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
```

It also does not introduce a new runtime feature or weaken the existing staged published-payload consumer matrix. Registry verification complements that matrix by testing the artifact users actually resolve after publication.
