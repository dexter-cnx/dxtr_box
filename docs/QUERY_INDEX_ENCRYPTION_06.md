# dxtr_box 0.6 — Query / Index + Encryption Hardening

## Scope

0.6 combines query/index polish and encryption hardening into one focused milestone. The goal is to make the existing query/index feature set production-ready for 1.0 without expanding Dxtr_Box into an ORM, sync engine, or schema framework.

Dxtr_Box is its own native local database for Flutter. Hive/Hive CE is not the product target; it remains an optional migration source, compatibility reference, and benchmark peer.

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

Do not add a fourth native profile. Do not introduce a Dart whole-box cache. Do not weaken AEAD authentication, durability, cross-process visibility, or public/storage change-control gates.

Dart 3.13 recorded-use/native tree shaking remains outside 0.6 unless explicitly pulled forward.

## Plaintext query/index baseline

Plaintext persisted indexes provide:

- named scalar indexes under `full`;
- dotted nested fields;
- equality and range candidate narrowing;
- deterministic planner selection;
- multi-index intersection for AND predicates;
- authoritative primary-record re-read and full predicate re-evaluation;
- one redb read snapshot per query;
- deterministic semantic sorting before pagination.

Persisted indexes narrow `where` candidates only. They do not satisfy ORDER BY.

## Accepted encrypted equality-index contract

PR2 implemented persisted encrypted indexes for equality narrowing only.

The persisted scalar representation is a deterministic 256-bit BLAKE2b keyed MAC derived from authenticated box key material and domain-separated by index name and field. The implementation reuses the BLAKE2 implementation already present through Argon2 rather than adding a second hash family solely for index tokens.

Required properties:

- no raw plaintext scalar bytes in encrypted index entries;
- deterministic matching only where equality semantics require it;
- domain separation by index name and field;
- numeric canonicalization aligned with query equality semantics;
- primary encrypted records remain ChaCha20Poly1305 authenticated ciphertext;
- every index candidate resolves through the authoritative primary record;
- every candidate is authenticated/decrypted and the full predicate is re-evaluated before returning to Dart;
- create/backfill/mutation/delete maintenance remains transactional with primary data;
- plaintext persisted scalar representation remains unchanged.

The equality token intentionally leaks equality classes/frequency for repeated indexed values. Index definitions expose index/field names; derived entries expose candidate record identifiers and approximate indexed cardinality. Plaintext scalar values and semantic value ordering are not intentionally persisted.

## Accepted encrypted range decision

PR3 made the encrypted ordered/range policy explicit: **encrypted range predicates remain scan-backed in 0.6**.

This applies to:

```text
>
>=
<
<=
between
```

The equality-token representation is not order-preserving and must never be used as fake range ordering.

Rejected for 0.6:

- keyed hash/MAC ordering — cryptographically unrelated to semantic scalar order and therefore incorrect;
- plaintext or reversibly encoded sortable scalar entries — violate the encrypted-index contract;
- order-preserving/order-revealing encryption — adds disproportionate order/distribution leakage plus cryptographic and durable-state complexity;
- bucketized range tokens — add leakage, false-positive/boundary/versioning/storage complexity without demonstrated product need.

For mixed `AND` predicates, encrypted equality terms may still narrow candidates. Ordered/range terms are evaluated only against authoritative authenticated/decrypted primary records.

Detailed decision record: `docs/ENCRYPTED_RANGE_DECISION_06.md`.

## Threat model / leakage

An attacker who obtains the database file may infer from encrypted equality-index state:

- index names and indexed field names;
- record identifiers present in an index;
- equality classes for repeated values;
- approximate frequency/cardinality;
- index presence for values according to index semantics.

The persisted equality token does not provide meaningful semantic ordering. Because encrypted range execution remains scan-backed, 0.6 does not add a persisted order-leakage channel.

Mutation correctness must prevent stale derived entries from surviving committed writes. Crash/reopen and lifecycle tests remain hard gates.

## Implementation sequence

### PR1 — threat model + safe-default regression guard + milestone/product docs

Completed and merged as PR #39.

### PR2 — encrypted equality index + plaintext planner/range/index polish + benchmark evidence

Completed and merged as PR #40.

PR2 delivered keyed BLAKE2b equality tokens, transactional encrypted index maintenance, equality-only encrypted candidate lookup, range scan fallback, lifecycle/regression coverage, query/index diagnostics, and native-size evidence within policy.

### PR3 — encrypted range/index decision

Completed and merged as PR #42.

Accepted outcome: retain scan-backed encrypted ordered/range execution. No order-preserving encrypted representation is added in 0.6.

Regression coverage locks:

- scan-equivalent results for all five ordered/range operators before and after encrypted index creation;
- mixed equality + range `AND` semantics;
- the planner rule that encrypted persisted candidate lookup is equality-only.

### PR4 — core reliability/API closure + 0.6 audit

Final milestone PR.

PR4 intentionally adds no feature expansion unless the audit exposes a concrete correctness issue. Its job is to synchronize release-facing documentation, record the accepted contracts, and require the full merge quality bar as final evidence.

Closure record: `docs/RELEASE_AUDIT_06.md`.

Do not turn PR4 into a Hive/Hive CE parity pass.

## Benchmark evidence policy

0.6 retains diagnostic timing rather than speed assertions.

Evidence surfaces include:

- plaintext scan vs persisted-index equality;
- plaintext scan vs persisted-index range;
- encrypted scan vs encrypted equality index;
- index create/backfill and mutation overhead where specifically measured;
- reopen/query correctness.

Run query/index diagnostics with:

```bash
make benchmark-query-index
```

Hosted-runner timing is non-gating. Do not publish or infer timing numbers unless produced by the corresponding benchmark run with methodology/toolchain context.

The encrypted range decision is primarily a security/complexity decision, not a claim that scanning is faster.

## Compatibility impact

0.6 preserves:

- the public Dart API shape except for changes explicitly introduced and guarded in earlier milestones;
- FRB 2.8.0 generated-binding reproducibility;
- primary storage format `dxtr_box/1`;
- exactly three native profiles;
- existing encrypted equality index representation after PR2;
- scan-backed encrypted range semantics after PR3;
- authoritative point-read and batch-read semantics from 0.5.

0.6 introduces no fourth profile, no order-revealing encrypted representation, no Dart whole-box cache, and no reusable stale read snapshot.

## Acceptance criteria

0.6 is complete only when:

1. plaintext query/index behavior is production-polished and regression-covered;
2. encrypted query/index leakage is explicitly documented;
3. encrypted equality indexing is securely implemented;
4. encrypted range indexing is either implemented under an explicit leakage contract or intentionally remains scan-only;
5. authoritative primary decrypt/authenticate + predicate recheck is preserved;
6. no plaintext scalar values are silently persisted for encrypted indexes;
7. no storage-format change is made without backward-read/migration evidence;
8. `dxtr_box/1` remains readable;
9. exactly `minimal | encryption | full` remain the native profiles;
10. Dart >=3.4 / Flutter >=3.22 remain supported;
11. FRB 2.8.0 generated bindings remain reproducible;
12. 0.5 read-path behavior does not regress unexpectedly;
13. query/index/migration/crash-reopen tests remain green;
14. native-size policy remains green;
15. staged Android/iOS/macOS/Linux/Windows consumers remain green;
16. public docs consistently position Dxtr_Box as a native local database, not as a Hive/Hive CE replacement;
17. PR4 passes `CI / Merge Gate / full quality bar` before the milestone is marked closed.

Detailed final matrix: `docs/RELEASE_AUDIT_06.md`.

## Product boundary

> A native local database for Flutter, backed by Rust/redb, with durable storage, declarative query/index support, first-class encryption, and simple box-style ergonomics.

Hive/Hive CE migration remains useful interoperability tooling, not the defining product direction.
