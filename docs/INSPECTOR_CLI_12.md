# Dxtr_Box 1.2 Inspector CLI

## Status

Milestone: 1.2

Issue: #95

The 1.2 milestone introduces a read-only Inspector CLI for existing Dxtr_Box databases. The CLI must reuse the authoritative Rust storage/core path and must not implement an independent parser for the `dxtr_box/1` durable format.

## Goals

- Inspect existing Dxtr_Box databases from a terminal without a Flutter host application.
- Keep all 1.2 inspection operations read-only.
- Provide deterministic human-readable output for interactive use.
- Provide deterministic JSON output for scripts and CI tooling.
- Preserve the existing `dxtr_box/1` durable format and all stable 1.x storage semantics.
- Reuse the same Rust/redb implementation used by the native Rust and Dart/FRB frontends.

## Non-goals

The 1.2 Inspector CLI does not add:

- record mutation, deletion, import, or repair commands;
- an interactive TUI;
- a new storage parser or storage format;
- storage migration;
- ORM/code generation;
- synchronization or replication;
- a Tokio requirement;
- a GPUI dependency;
- a fourth native feature profile.

## Proposed command surface

The initial command surface is intentionally small:

```text
dxtr-box-inspect --help
dxtr-box-inspect --version
dxtr-box-inspect <path> boxes
dxtr-box-inspect <path> keys <box> [--offset N] [--limit N]
dxtr-box-inspect <path> get <box> <key>
dxtr-box-inspect <path> indexes <box>
```

All data-producing commands should support:

```text
--format text
--format json
```

`text` is the default. JSON output must be stable enough for CI/tooling consumption and must not contain incidental diagnostic text on stdout.

## Read-only invariant

The Inspector CLI must not expose any command that mutates user data in 1.2.

Implementation must also avoid hidden mutations caused by inspection. Tests must prove that representative database files are byte-for-byte unchanged after inspection where the underlying storage engine permits stable byte comparison; otherwise tests must prove equivalent reopen-visible state and unchanged logical contents/metadata.

The CLI must use the authoritative core/open path rather than directly decoding redb tables from a parallel implementation.

## Output and exit-code contract

Stdout is reserved for requested command output. Diagnostics go to stderr.

Initial exit-code classes:

- `0`: success;
- `2`: CLI usage/argument error;
- `3`: database path/open failure;
- `4`: requested box/key not found;
- `5`: decode/authentication failure;
- `6`: unsupported capability/profile;
- `1`: unexpected internal failure.

Exact error variants may evolve during PR1/PR2, but tests must pin the final 1.2 contract before release.

## Encryption

Encrypted databases remain inspectable only when the caller supplies valid key material through an explicitly supported mechanism. Secrets must never be echoed in text/JSON output or normal diagnostics.

The implementation should prefer a mechanism that avoids placing raw secrets in process listings. The final mechanism and threat-model note must be documented before PR3 closes.

## Pagination and large boxes

Key enumeration must be deterministic and bounded. `keys` must support `--offset` and `--limit`; implementation must avoid eagerly materializing an entire large box solely to return a small requested page when the core can provide a bounded traversal.

Default and maximum limits will be pinned by tests once the core integration shape is known.

## Delivery plan

### PR1 — Contract + skeleton

- Pin command names and read-only contract.
- Add CLI crate/bin structure using the existing Rust workspace/package topology.
- Add `--help` and `--version`.
- Implement database open and `boxes` if the authoritative core exposes the required enumeration cleanly; otherwise add the smallest core read-only inspection seam needed.
- Add smoke tests and CI wiring.

### PR2 — Record/index inspection

- `keys` with deterministic pagination.
- `get` by key.
- `indexes` metadata.
- Text and JSON output contracts.
- Stable not-found behavior and exit codes.

### PR3 — Hardening

- Encrypted database/key handling.
- Large-box and malformed/corrupt input behavior.
- Read-only invariant tests.
- Performance/regression evidence.
- Cross-platform CLI build coverage where supported by the package topology.

### PR4 — 1.2 closure

- README usage.
- Code walkthrough and handoff sync.
- Package/release documentation.
- Existing Dart/Flutter/Rust compatibility gates remain green.
- Hosted consumer/release validation remains green.
- Release `1.2.0` with no durable-format migration.

## Quality gates

The milestone does not weaken existing gates. New CLI work must additionally pass:

- `cargo fmt --check`;
- clippy with repository policy;
- Rust unit/integration tests;
- CLI help/version smoke tests;
- deterministic text/JSON golden or contract tests;
- read-only invariant tests;
- existing cross-frontend compatibility tests;
- existing durable-format/API guards;
- existing Flutter/Dart validation.

## Compatibility constraints

Unless separately justified and approved during the milestone, 1.2 keeps:

- durable format `dxtr_box/1`;
- Dart >= 3.4;
- Flutter >= 3.22;
- the current FRB/redb dependency baselines;
- native profiles exactly `minimal | encryption | full`;
- no mandatory async runtime.
