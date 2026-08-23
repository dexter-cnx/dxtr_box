# Dxtr_Box 0.9 — Conformance & Startup Maturity

## Goal

0.9 is a bounded product-maturity milestone after the completed 0.8 multi-frontend foundation.

The milestone strengthens confidence that every supported frontend obeys the same storage contract, then uses that contract as the safety net for startup-path optimization. It does not add a third storage engine, a new durable format, ORM/schema generation, sync, or a fourth native profile.

## Proposed sequence

```text
PR1 — reusable cross-frontend storage conformance test kit
PR2 — schema/index config fingerprint design + correctness guards
PR3 — startup/reopen fast path + benchmark evidence, only if PR2 evidence justifies it
PR4 — cross-frontend closure audit + docs/version sync
```

PR2/PR3 may be collapsed or PR3 may become a documented no-op decision if profiling shows startup reconciliation is not material.

## PR1 — conformance kit

PR1 keeps the first version internal under `rust/tests/support/`.

One reusable `StorageBoxContract` is executed against:

- the first-class Rust-native `BoxHandle` frontend;
- the FRB adapter surface used by Dart.

The shared contract currently validates:

- missing-key behavior;
- put/get/contains semantics;
- overwrite without length growth;
- bulk put;
- one-snapshot-style `get_all` observable semantics: input hit order, duplicate hits, omitted misses;
- key enumeration;
- idempotent missing delete;
- delete and delete-all behavior;
- clear and final empty state.

Because PR1 is CRUD-only, the same integration test participates in `cargo test --all-targets` for all existing native profiles:

```text
minimal
minimal + encryption
full
```

The kit is intentionally internal first. A separate public test package/crate should only be introduced if downstream adapter or frontend authors demonstrate a real need.

## Invariants

0.9 must preserve:

- one authoritative Rust core;
- `dxtr_box/1` durable format;
- redb 2.1.0;
- flutter_rust_bridge 2.8.0;
- exactly `minimal | encryption | full`;
- authenticated encryption semantics;
- authoritative primary-record predicate rechecks;
- encrypted equality narrowing and scan-backed encrypted range predicates;
- dynamic-first Dart API;
- Rust-native synchronous API with no Tokio commitment.

## Fingerprint/startup rules for later PRs

A future schema/index configuration fingerprint is acceptable only if all of the following hold:

1. fingerprint inputs are deterministic and versioned;
2. a match skips only redundant reconciliation work;
3. durable format compatibility checks are never skipped;
4. changed or unknown configuration always falls back to authoritative reconciliation;
5. cross-frontend conformance remains green;
6. cold-open/reopen benchmarks show material value before claiming an optimization.

No storage-format bump is implied by creating a derived metadata fingerprint; any durable metadata addition still requires explicit compatibility review.
