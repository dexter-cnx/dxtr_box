# Dxtr_Box 1.2 Release Audit

## Release candidate

Target versions:

- Flutter/Dart package: `dxtr_box 1.2.0`
- Rust crate: `rust_lib_dxtr_box 1.2.0`
- Inspector binary: `dxtr-box-inspect`

The durable format remains `dxtr_box/1` and no migration is introduced.

## 1.2 scope delivered

- Read-only Inspector CLI over existing database directories.
- Deterministic box listing and bounded key pagination.
- Raw record inspection and full-profile semantic BoxCodec-compatible decoding.
- Persisted index inspection where supported.
- Encrypted record inspection using the existing Argon2 + ChaCha20Poly1305 implementation and record-key AAD.
- Secret input through exact UTF-8 stdin via `--key-stdin`; no raw key argument is exposed.
- Deterministic text/JSON output and stable exit-code classes 0/1/2/3/4/5/6.
- Snapshot-copy read seam that avoids the ordinary runtime open path and preserves source database bytes in regression coverage.

## Compatibility retained

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
durable format = dxtr_box/1
```

No TUI, write/edit/import command, storage migration, ORM/code generation, synchronization layer, GPUI dependency, Tokio requirement, fourth profile, or public Dart API redesign is part of 1.2.

## Packaging readiness

The Rust package includes the `dxtr-box-inspect` binary through the crate `[[bin]]` target. Local installation is expected to work with:

```bash
cargo install --path rust --bin dxtr-box-inspect
```

After crates.io publication:

```bash
cargo install rust_lib_dxtr_box --version 1.2.0 --bin dxtr-box-inspect
```

The Flutter package and Rust crate versions must remain aligned at 1.2.0 before registry publication.

## Required green evidence before publish

- Fast CI: format, analyze, clippy and mandatory tests.
- Rust tests for `minimal`, `encryption`, and `full`.
- Inspector semantic decode, encryption, malformed-input and source-byte invariants.
- Native integration and cross-frontend conformance.
- Dart isolate concurrency and real-world/read-path evidence workflows where triggered.
- Rust crate package readiness / `cargo package` verification.
- Dart/pub package dry-run and staged Android/iOS/macOS/Linux/Windows consumer builds.
- Review threads resolved and merge gate green.

## Publication order

1. Merge the 1.2 closure PR only after the complete required gate is green.
2. Tag/release `1.2.0` from the merged release commit.
3. Publish `rust_lib_dxtr_box 1.2.0` to crates.io and verify the hosted crate/binary installation.
4. Publish `dxtr_box 1.2.0` to pub.dev.
5. Run hosted registry consumer verification against the actual published 1.2.0 artifacts.

Repository version metadata alone is not proof that either registry publication completed successfully.
