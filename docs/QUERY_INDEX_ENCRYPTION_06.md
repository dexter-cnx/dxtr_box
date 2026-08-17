# dxtr_box 0.6 — Query / Index + Encryption Hardening

## Scope

0.6 combines query/index polish and encryption hardening into one focused milestone. The goal is to make the existing query/index feature set production-ready for 1.0 without expanding Dxtr_Box into an ORM, sync engine, or schema framework.

Dxtr_Box is its own native local database for Flutter. Hive/Hive CE is not the product target; it remains an optional migration source, compatibility reference, and benchmark peer.

The milestone has three bounded tracks:

1. query / index polish;
2. encrypted query / index hardening;
3. compatibility/migration improvements only when they materially improve adoption.

## Stable constraints

Preserve throughout 0.6:

```text
Dart >= 3.4
Flutter >= 3.22
native library = rust_lib_dxtr_box
native profiles = minimal | encryption | full
format_version = dxtr_box/1
flutter_rust_bridge = 2.8.0
redb = 2.1.0
```

Do not add a fourth native profile. Do not introduce a Dart whole-box cache. Do not weaken AEAD authentication, durability, cross-process visibility, or the public/storage change-control gates.

Dart 3.13 recorded-use/native tree shaking remains outside 0.6 unless explicitly pulled forward.

## Current baseline

Plaintext persisted indexes already provide:

- named scalar indexes under the `full` profile;
- dotted nested fields;
- equality and range candidate narrowing;
- deterministic planner selection;
- multi-index intersection for AND predicates;
- authoritative primary-record re-read and full predicate re-evaluation;
- one redb read snapshot per query;
- deterministic semantic sorting before pagination.

Persisted indexes currently narrow `where` candidates only. They do not satisfy ORDER BY.

Encrypted boxes currently support native scan queries, but `createIndex` rejects encrypted boxes with the explicit error:

```text
persisted indexes are not yet supported for encrypted boxes; native scan queries remain available
```

That rejection is intentional and remains the safe default until 0.6 proves a representation and leakage contract.

## Security contract for encrypted indexes

An encrypted index must not silently expose plaintext field values merely to recover plaintext-index performance.

The 0.6 design must explicitly document what an attacker who obtains the database file can infer from index state. At minimum, evaluate leakage of:

- indexed field names;
- record identifiers;
- equality classes / repeated values;
- value ordering;
- approximate cardinality / frequency;
- null / missing state;
- mutation history if stale derived entries can survive failure.

The implementation must not call an encrypted index "secure" if it intentionally preserves ordering or equality information without documenting that leakage.

Primary encrypted records remain ChaCha20Poly1305 authenticated ciphertext. Every candidate returned by an encrypted index must still be resolved through the authoritative primary record, authenticated/decrypted, and fully re-evaluated against the predicate before it can be returned to Dart.

## 0.6 implementation sequence

### PR 1 — encrypted-index threat model + representation decision

- freeze the leakage/threat model;
- evaluate equality-only keyed tokens versus order-preserving/range-capable designs;
- reject designs whose leakage is disproportionate to the product benefit;
- add contract tests that keep encrypted index creation blocked until an accepted representation exists;
- define upgrade/storage implications before changing `dxtr_box/1` derived index state;
- align README/handoff/product positioning with Dxtr_Box as its own native local database.

Default preference: support less functionality securely rather than exposing plaintext-compatible scalar bytes.

### PR 2 — encrypted equality index + plaintext query/index polish

This PR intentionally combines the former encrypted-equality and plaintext-planner PRs because they share the same index representation, planner, maintenance, and benchmark surfaces.

Preferred encrypted target is equality indexing only, using keyed deterministic tokens derived from authenticated box key material and index context.

Encrypted requirements:

- no raw plaintext scalar in index entries;
- domain separation per index/field;
- deterministic equality matching only;
- candidate record keys remain derived state, never authoritative;
- full primary decrypt/authenticate + predicate recheck;
- index create/backfill/mutation/delete in the same transactional correctness model as plaintext indexes;
- reopen, wrong-key, tamper, crash/reopen, migration, drop/recreate tests;
- explicit documentation that equality frequency can still be observable if deterministic tokens are persisted.

Plaintext/planner requirements:

- verify equality/range/AND planner behavior remains deterministic;
- benchmark plaintext index narrowing after 0.5 read-path changes;
- inspect scalar encoding and range scan cost;
- evaluate whether scalar-level redb range seeks materially outperform the current candidate decoding/filtering path;
- keep full predicate re-evaluation mandatory;
- do not add index-backed ORDER BY unless measurements and implementation simplicity justify it.

Do not extend encrypted equality tokens to range operators by pretending keyed hashes are order-preserving.

### PR 3 — encrypted range/index decision

Encrypted range indexing is optional, not a milestone requirement.

If no design provides acceptable leakage, complexity, and maintenance cost, 0.6 must explicitly retain scan fallback for encrypted range predicates rather than shipping order-leaking storage by default.

A documented rejection is an acceptable outcome.

### PR 4 — compatibility cleanup + closure audit

Close only compatibility/migration gaps that materially improve adoption and remain consistent with the native-database product direction, then run the 0.6 closure audit and full merge quality bar.

Do not pull in:

- ORM/code generation;
- cloud replication/sync;
- general schema framework;
- reactive query engine redesign;
- Web/IndexedDB unless separately prioritized;
- LazyBox direct file parsing unless separately justified.

## Benchmark evidence

0.6 should retain diagnostic timing rather than speed assertions.

Add/extend evidence for:

- plaintext scan vs persisted-index equality;
- plaintext scan vs persisted-index range;
- encrypted scan vs encrypted equality index if implemented;
- index create/backfill cost;
- mutation overhead with indexes enabled;
- reopen/query behavior;
- representative 100 / 1,000 / 10,000 record datasets where CI cost remains reasonable.

Every performance claim must include methodology, runner/toolchain metadata, and correctness validation.

## Acceptance criteria

0.6 is complete only when:

1. plaintext query/index behavior is production-polished and regression-covered;
2. encrypted query/index leakage is explicitly documented;
3. encrypted equality indexing is either implemented securely or rejected with evidence;
4. encrypted range indexing is either implemented under an explicit leakage contract or intentionally remains scan-only;
5. authoritative primary decrypt/authenticate + predicate recheck is preserved;
6. no plaintext scalar values are silently persisted for encrypted indexes;
7. no storage-format change is made without backward-read/migration evidence;
8. `dxtr_box/1` remains readable;
9. exactly `minimal | encryption | full` remain the native profiles;
10. Dart >=3.4 / Flutter >=3.22 remain supported;
11. FRB 2.8.0 generated bindings remain reproducible;
12. 0.5 read-path behavior and benchmarks do not regress unexpectedly;
13. query/index/migration/crash-reopen tests remain green;
14. native-size policy remains green;
15. staged Android/iOS/macOS/Linux/Windows consumers remain green;
16. public docs consistently position Dxtr_Box as a native local database, not as a Hive/Hive CE replacement.

## Product boundary

The intended product identity remains compact:

> A native local database for Flutter, backed by Rust/redb, with durable storage, declarative query/index support, first-class encryption, and simple box-style ergonomics.

Hive/Hive CE migration remains useful interoperability tooling, not the defining product direction.

0.6 strengthens those existing differentiators rather than adding a new product category.
