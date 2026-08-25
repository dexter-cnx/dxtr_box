# 1.0 Release Candidate Evidence

This document records the release-candidate evidence required before the final `1.0.0` audit. It does not declare the package stable by itself.

## Baseline

- PR1 contract-freeze audit is merged.
- PR2 public API semantic regression coverage is merged.
- Current stabilization version remains `0.10.0-dev.1` until the final release PR.
- Durable storage identity remains `dxtr_box/1`.
- Native profiles remain exactly `minimal`, `encryption`, and `full`.
- Dart >= 3.4 and Flutter >= 3.22 remain the compatibility floor.

## Evidence matrix

| Release risk | Executable evidence | Expected result |
| --- | --- | --- |
| Published payload accidentally depends on repository-only files | `tool/validate_published_consumer.dart` stages `.pubignore` output and rejects forbidden paths | staged payload is self-contained |
| Published package cannot compile in a real host | CI platform-consumer jobs build generated Android, iOS, macOS, Linux, and Windows apps against the staged payload | all supported platform consumers build |
| Public API disappears from the staged package | generated consumer references `BoxStore`, deprecated `DxtrBox`, query builder/model, index declaration, and Hive CE migration entry point | public surfaces compile from published payload |
| Durable data cannot be reopened | `test/native_integration_test.dart` performs Dart -> FRB -> Rust -> redb writes, closes, reopens, and verifies persisted values | reopen preserves stored values |
| Encrypted durable data cannot be reopened safely | native integration test closes/reopens encrypted boxes and rejects missing/wrong keys | correct key reopens; invalid key paths fail |
| Migration destination lifecycle regresses | `test/migration_destination_test.dart` verifies reservation cleanup and ordinary reopen after reservation release | failed migration leaves no destination; successful release permits reopen |
| Storage/API contract drifts during release preparation | `make contract-check`, public API contract tests, and semantic regression tests | package/native/storage identities and documented semantics remain frozen |
| Generated FRB bindings drift | CI FRB generated-bindings job regenerates and requires a clean diff | generated bindings remain current |
| Native feature topology changes unexpectedly | CI tests exactly minimal, encryption, and full profiles | all three profiles pass; no fourth profile introduced |

## Upgrade interpretation

The pre-1.0 line has retained the same durable storage marker, `dxtr_box/1`. Therefore the release-candidate upgrade claim is deliberately narrow:

1. existing `dxtr_box/1` databases must remain readable after reopen;
2. encrypted databases must preserve key requirements;
3. migration helpers must continue to protect destination creation and cleanup;
4. the staged consumer package must compile without repository-only dependencies.

This is not evidence for an older or alternate durable format. No storage-format migration is introduced in 1.0 stabilization.

## PR3 acceptance criteria

PR3 is complete when:

- staged published consumers build on Android, iOS, macOS, Linux, and Windows;
- the staged consumer compile smoke covers the principal public 1.0 surfaces, not only the legacy compatibility type;
- native persistence/reopen, encrypted reopen, migration destination, contract, FRB, and three-profile gates remain green;
- package/docs dry-run remains green;
- there are no unresolved reviewer findings.

After this PR merges, the remaining step is PR4: final release audit, README/CHANGELOG/handoff/walkthrough sync, and version `1.0.0`.
