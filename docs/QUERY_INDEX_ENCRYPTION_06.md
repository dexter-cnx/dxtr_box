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

## Baseline entering PR2

Plaintext persisted indexes already provide:

- named scalar indexes under the `full` profile;
- dotted nested fields;
- equality and range candidate narrowing;
- deterministic planner selection;
- multi-index intersection for AND predicates;
- authoritative primary-record re-read and full predicate re-evaluation;
- one redb read snapshot per query;
- deterministic semantic sorting before pagination.

Persisted indexes narrow `where` candidates only. They do not satisfy ORDER BY.

PR1 kept encrypted persisted-index creation blocked while the leakage contract and representation were being selected. PR2 intentionally changes that safe default only for equality narrowing.

## Accepted encrypted equality-index contract

PR2 accepts persisted encrypted indexes for equality narrowing only.

The persisted scalar representation is a deterministic 256-bit BLAKE2b keyed MAC derived from authenticated box key material and domain-separated by index name and field. The implementation reuses the BLAKE2 implementation already present through Argon2 rather than adding a second hash family solely for index tokens.

Required properties:

- no raw plaintext scalar bytes in encrypted index entries;
- deterministic matching only where equality semantics require it;
- domain separation by index name and field;
- numeric canonicalization aligned with query equality semantics;
- primary encrypted records remain ChaCha20Poly1305 authenticated ciphertext;
- every index candidate is resolved through the authoritative primary record;
- every candidate is authenticated/decrypted and the full predicate is re-evaluated before returning to Dart;
- create/backfill/mutation/delete maintenance remains in the same redb transactional correctness model as primary data;
- plaintext persisted scalar representation remains unchanged;
- ordered/range predicates on encrypted boxes do not use the equality-token representation and fall back to authoritative scan.

The token is not encryption and is not described as hiding equality relationships. Deterministic equality indexes intentionally leak equality classes/frequency for repeated indexed values. Persisted index definitions also expose index names and indexed field names, while candidate entries expose record identifiers and approximate indexed cardinality. These are accepted, documented tradeoffs for equality narrowing; plaintext scalar values and value ordering are not intentionally persisted.

## Threat model / leakage

An attacker who obtains the database file may infer from encrypted derived index state:

- index names and indexed field names;
- record identifiers present in an index;
- equality classes for repeated values through repeated deterministic tokens;
- approximate frequency/cardinality;
- presence or absence of index entries for null/missing/non-indexable values according to index semantics.

The equality-token representation does not provide meaningful value ordering. Do not extend it to `>`, `>=`, `<`, `<=`, or `between` by treating keyed hashes as order-preserving.

Mutation correctness must prevent stale derived entries from surviving committed writes. Crash/reopen and lifecycle tests remain part of the hard quality bar.

## PR2 implementation state

PR2 implements:

- encrypted `createIndex` and transactional backfill;
- deterministic equality tokens using BLAKE2b keyed MAC (256-bit);
- encrypted index maintenance for `put`, `putAll`, `delete`, and `deleteAll`;
- equality-only candidate lookup for encrypted boxes;
- encrypted range/ordered predicate scan fallback;
- authoritative decrypt/authenticate + full predicate recheck for every candidate;
- reopen/lifecycle coverage for encrypted indexes;
- plaintext planner behavior without changing plaintext persisted scalar representation;
- diagnostic query/index benchmark coverage for plaintext scan/index scenarios and encrypted equality scan/index scenarios.

Native-size policy is preserved. After replacing a larger BLAKE3 dependency with the BLAKE2 implementation already present through Argon2, the measured full-profile Linux x64 artifact moved from 2,385,720 to 2,416,152 bytes: +30,432 bytes / +1.276%, within policy. Minimal and encryption profiles changed only marginally.

CI run `32069766813` on commit `5346c1176b2753cea9fc248b60055215041815c9` passed the Draft validation set including Fast CI, Dart tests, all three Rust profiles, native integration, storage/query regression, FRB drift, minimum SDK, native-size policy, all five platform consumers, benchmark smoke/comparison, and Merge Gate.

The dedicated query/index timing harness is diagnostic only. Run it with:

```bash
make benchmark-query-index
```

Shared-runner timing must not become a pass/fail performance threshold. Correctness, authoritative recheck, durability, and the security contract remain the hard gates.

## 0.6 implementation sequence

### PR 1 — encrypted-index threat model + representation decision

Completed. PR1 froze the threat model, documented the safe default, and aligned product positioning before changing durable derived index state.

### PR 2 — encrypted equality index + plaintext query/index polish

Current runtime PR.

The accepted target is equality indexing only using keyed deterministic tokens derived from authenticated box key material and index context.

PR2 closes only after implementation, regression coverage, diagnostic benchmark harness/evidence, documentation sync, and final full merge validation are complete.

### PR 3 — encrypted range/index decision

Encrypted range indexing is optional, not a milestone requirement.

If no design provides acceptable leakage, complexity, and maintenance cost, 0.6 must explicitly retain scan fallback for encrypted range predicates rather than shipping order-leaking storage by default.

A documented rejection is an acceptable outcome.

### PR 4 — core reliability/API closure + 0.6 audit

Close only reliability/API/interoperability gaps that independently strengthen Dxtr_Box as a native local database, then run the 0.6 closure audit and full merge quality bar.

Do not turn this into a Hive/Hive CE parity pass.

Do not pull in:

- ORM/code generation;
- cloud replication/sync;
- general schema framework;
- reactive query engine redesign;
- Web/IndexedDB unless separately prioritized;
- LazyBox direct file parsing unless separately justified.

## Benchmark evidence policy

0.6 retains diagnostic timing rather than speed assertions.

Evidence surfaces include:

- plaintext scan vs persisted-index equality;
- plaintext scan vs persisted-index range;
- encrypted scan vs encrypted equality index;
- index create/backfill cost where specifically measured;
- mutation overhead with indexes where specifically measured;
- reopen/query correctness;
- representative dataset sizes that keep CI/runtime cost reasonable.

Every published performance claim must include methodology and correctness validation. Do not manufacture or infer timing numbers from a correctness-only CI run.

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
