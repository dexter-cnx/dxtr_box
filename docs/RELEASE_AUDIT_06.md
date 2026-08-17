# dxtr_box 0.6 Release Audit

## Purpose

This document is the closure record for **0.6 — Query / Index + Encryption Hardening**.

The milestone is intentionally narrow: production-polish query/index behavior, add a secure encrypted equality-index path, make the encrypted range decision explicit, and preserve the existing storage/API/runtime compatibility contract. It is not a Hive/Hive CE parity milestone.

## Delivered sequence

- PR #39 — threat model, safe-default guard, product/milestone documentation.
- PR #40 — encrypted equality indexes using deterministic keyed BLAKE2b MAC tokens, transactional index maintenance, equality-only encrypted candidate narrowing, planner/query benchmark diagnostics, native-size evidence.
- PR #42 — explicit decision to keep encrypted ordered/range predicates scan-backed, with regression coverage for all range operators and mixed equality + range predicates.
- PR4 — this closure/audit PR; no feature expansion.

## Security contract

Encrypted persisted indexes may reveal index/field names, record identifiers, approximate cardinality, and equality classes/frequency for repeated values.

They must not persist raw plaintext scalar values or a semantic ordering representation.

Encrypted query candidates always follow the authoritative path:

```text
candidate key
  -> primary record
  -> ChaCha20Poly1305 authenticate/decrypt
  -> full predicate re-evaluation
  -> sort / offset / limit
  -> Dart result
```

Encrypted equality predicates may use persisted keyed tokens for narrowing. `>`, `>=`, `<`, `<=`, and `between` remain scan-backed.

## Compatibility matrix

The closure PR must preserve all of the following:

| Contract | Required state |
|---|---|
| Dart | `>= 3.4.0 < 4.0.0` |
| Flutter | `>= 3.22.0` |
| flutter_rust_bridge | `2.8.0` exactly |
| redb | `2.1.0` |
| native library | `rust_lib_dxtr_box` |
| native profiles | exactly `minimal | encryption | full` |
| durable format | `dxtr_box/1` readable |
| public read semantics | authoritative `get`, `containsKey`, one-snapshot `getAll` |
| encryption | full AEAD authentication retained |
| cross-process visibility | no Dart whole-box cache / no implicit stale read session |

## Acceptance audit

0.6 is considered complete only when the final PR's full merge quality bar proves:

- plaintext query/index regressions are green;
- encrypted equality index lifecycle/mutation/reopen coverage is green;
- encrypted range scan-equivalence and planner guards are green;
- public API/storage contract checks are green;
- `dxtr_box/1` compatibility remains green;
- migration and process crash/reopen coverage are green;
- FRB generated bindings are reproducible;
- all three Rust capability profiles are green;
- native-size regression policy is green;
- package/pub readiness is green;
- Android, iOS, macOS, Linux, and Windows staged consumers are green;
- benchmark correctness/smoke gates remain green.

Hosted timing measurements remain diagnostic and non-gating.

## No-change decisions

PR4 deliberately does not add:

- encrypted range/order-revealing storage;
- index-backed ORDER BY;
- a fourth native profile;
- a Dart whole-box cache;
- a reusable long-lived read snapshot/session;
- ORM/schema generation;
- cloud sync, backend adapters, vector clocks, or CRDTs;
- Hive/Hive CE parity work solely for parity's sake.

## Release conclusion

When `CI / Merge Gate / full quality bar` is green for this PR, **0.6 Query / Index + Encryption Hardening is closed**. The next implementation work should start from the post-0.6 maturity backlog rather than extending 0.6 opportunistically.
