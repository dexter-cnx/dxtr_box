# Dxtr_Box 0.9 — Conformance & Startup Maturity

## Goal

0.9 is a bounded product-maturity milestone after the completed 0.8 multi-frontend foundation.

The milestone strengthens confidence that every supported frontend obeys the same storage contract, then uses that contract as the safety net for startup-path investigation. It does not add a third storage engine, a new durable format, ORM/schema generation, sync, or a fourth native profile.

## Sequence

```text
PR1 — reusable cross-frontend storage conformance test kit                  merged
PR2 — schema/index config fingerprint design + correctness guards           current
PR3 — cold-open/reopen benchmark + fast-path implementation only if justified
PR4 — cross-frontend closure audit + docs/version sync
```

PR3 is explicitly allowed to conclude with an evidence-backed no-op runtime decision when profiling shows the existing startup path is already bounded and cheap.

## PR1 — conformance kit

PR1 keeps the first version internal under `rust/tests/support/`.

One reusable `StorageBoxContract` is executed against:

- the first-class Rust-native `BoxHandle` frontend;
- the FRB adapter surface used by Dart.

The shared contract validates:

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

## PR2 — fingerprint decision

PR2 concludes that Dxtr_Box should **not persist a schema/index configuration fingerprint yet**.

The current product has no consumer-supplied schema or desired-index manifest at open time. Persisted `index_definitions` are themselves the authoritative configuration, and open does not run an automatic schema/index reconciliation or rebuild pass. A hash derived from the same definitions would therefore be tautological durable state rather than a meaningful fast-path discriminator.

`rust/tests/config_fingerprint_decision.rs` adds full-profile correctness guards through both Rust-native and FRB-adapter surfaces:

- dynamic index creation remains first-class;
- index definitions survive reopen;
- dynamic index removal remains first-class;
- removed configuration survives another reopen;
- both frontends observe the same durable configuration semantics.

See `docs/CONFIG_FINGERPRINT_DECISION_09.md` for the rejected design, revisit criteria, and PR3 benchmark rule.

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

## Fingerprint/startup rules

A future schema/index configuration fingerprint is acceptable only if all of the following hold:

1. there is an independently meaningful expected configuration to compare with durable state;
2. fingerprint inputs are deterministic and versioned;
3. a match skips identified redundant reconciliation work;
4. durable format compatibility checks are never skipped;
5. encryption/key validation is never skipped;
6. changed, absent, or unknown configuration always falls back to authoritative reconciliation;
7. cross-frontend conformance remains green;
8. cold-open/reopen benchmarks show material value before claiming an optimization.

No storage-format bump is implied by derived metadata, but any durable metadata addition still requires explicit compatibility review.

## PR3 evidence rule

PR3 must measure the startup path before changing it. The benchmark should distinguish at minimum:

- new empty box creation;
- reopen of an empty existing box;
- reopen with records but no indexes;
- reopen with persisted index definitions;
- plaintext and encrypted reopen where supported.

Record count and index-count scaling should be inspected separately. If no material startup cost attributable to reconciliation exists, PR3 should document that result and avoid speculative runtime state.
