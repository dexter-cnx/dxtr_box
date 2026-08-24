# 0.9 Release Audit — Conformance & Startup Maturity

Milestone **0.9 — Conformance & Startup Maturity** closes after four bounded PRs.

## Scope completed

### PR1 — reusable cross-frontend conformance kit

Added an internal reusable `StorageBoxContract` and ran the same CRUD/batch/deletion semantics against the Rust-native frontend and the FRB-adapter frontend.

Covered behaviors include:

- empty/missing keys;
- put/get/contains;
- overwrite without length growth;
- bulk put;
- ordered `get_all` hits with duplicate preservation and miss omission;
- key enumeration;
- idempotent missing delete;
- delete/delete-all;
- clear and final empty state.

This sits alongside the existing bidirectional same-file compatibility tests:

```text
Rust-native write -> close -> FRB-adapter read
FRB-adapter write -> close -> Rust-native read
```

## PR2 — configuration fingerprint decision

The milestone intentionally did **not** add a persisted schema/index fingerprint.

Reason: Dxtr_Box has no consumer-supplied desired schema/index manifest at open time. Persisted `index_definitions` are already the authoritative durable configuration and startup performs no expensive automatic reconciliation/rebuild pass that a second hash could safely skip.

Correctness guards were added so future startup work cannot accidentally replace the current dynamic-first index lifecycle with implicit schema registration.

## PR3 — startup/reopen evidence

A reproducible benchmark matrix now measures existing open/reopen behavior for:

```text
records: 0 | 1,000 | 10,000
indexes: 0 | 1 | 4
```

Each case records:

```text
first_open_us
reopen_p50_us
reopen_p95_us
reopen_max_us
```

Hosted Linux x64 evidence showed reopen p95 remaining below 1 ms across the matrix, with no material growth at 10,000 records / 4 persisted indexes. Therefore 0.9 intentionally adds **no startup fast path, no startup cache, and no fingerprint metadata**.

The benchmark runner also rejects zero iterations and never recursively deletes a caller-supplied root; it uses only its dedicated `dxtr-box-startup-benchmark` child.

Run:

```bash
bash tool/startup_benchmark.sh
```

The existing multi-frontend benchmark runner also captures startup evidence in the same CI artifact.

## PR4 — closure synchronization

PR4 performs the release audit, updates package/docs status, and advances the package development version to `0.9.0-dev.1`. It does not change runtime semantics or durable storage.

## Preserved invariants

0.9 preserves:

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
durable format = dxtr_box/1
```

It also preserves:

- one authoritative Rust/redb storage engine;
- one durable format shared by Dart/FRB and Rust-native frontends;
- authenticated encryption requirements;
- dynamic-first query/index configuration;
- no Dart whole-box cache;
- no fourth native profile;
- no ORM/schema registration requirement;
- no GPUI dependency in the core package.

## Evidence interpretation

The benchmark outputs are diagnostic evidence, not marketing claims. Do not compare runs from different machines, build modes, record counts, or workload settings as direct speedup ratios.

The evidence-backed 0.9 conclusion is conservative: current startup is already bounded enough that additional durable metadata or runtime shortcuts would add complexity without demonstrated benefit.
