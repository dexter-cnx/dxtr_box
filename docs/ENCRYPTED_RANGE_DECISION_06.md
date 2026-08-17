# dxtr_box 0.6 — Encrypted Range Index Decision

## Decision

For 0.6, encrypted ordered/range predicates remain **scan-backed**. Dxtr_Box will not persist an order-preserving encrypted range index.

This applies to:

- `>`
- `>=`
- `<`
- `<=`
- `between`

Encrypted equality indexing remains supported through the PR2 deterministic keyed-token design. Equality candidates are still only a narrowing hint: the authoritative encrypted primary record is re-read, ChaCha20Poly1305-authenticated/decrypted, and the full predicate is re-evaluated before any result is returned.

## Why this is the accepted design

The current equality-token representation deliberately reveals equality classes/frequency but not scalar order. It is suitable for exact matching because a keyed deterministic MAC can answer equality without pretending to preserve ordering.

A persisted encrypted range index would require additional structure that leaks substantially more information or adds disproportionate complexity.

### Rejected: keyed hash/MAC ordering

A keyed hash or MAC has no useful relation to the semantic order of the underlying scalar. Sorting or range-seeking token bytes would be incorrect. Dxtr_Box must never treat deterministic equality tokens as an order-preserving representation.

### Rejected: plaintext or reversibly encoded scalar index bytes

Persisting the same sortable scalar representation used by plaintext indexes would directly expose indexed values/order and would violate the encrypted-index contract established in PR1/PR2.

### Rejected for 0.6: order-preserving / order-revealing encryption

Order-preserving or order-revealing schemes intentionally disclose relative ordering and can amplify distribution/frequency leakage. Introducing such a primitive would materially change the threat model, durable derived-state contract, cryptographic review burden, and dependency/native-size surface.

The product value does not justify that expansion in 0.6.

### Rejected for 0.6: bucketized range tokens

Bucketized representations can reduce some leakage but introduce false positives, boundary semantics, token-versioning, tuning policy, and potentially multiple persisted tokens per value. Primary predicate recheck would preserve correctness, but the maintenance/storage/complexity cost is not justified for the current milestone.

## Leakage contract retained

With the accepted 0.6 design, an attacker who obtains the database file may infer from encrypted equality indexes:

- index/field names stored as index metadata;
- candidate record identifiers present in derived index entries;
- equality classes for repeated indexed values;
- approximate frequency/cardinality for deterministic equality tokens.

The persisted equality token itself does **not** provide semantic scalar ordering.

Encrypted ordered/range predicates therefore do not add a new persisted order-leakage channel in 0.6.

## Planner contract

For encrypted boxes:

```text
Equal                  -> keyed equality index may narrow candidates
GreaterThan            -> scan
GreaterThanOrEqual     -> scan
LessThan               -> scan
LessThanOrEqual        -> scan
Between                -> scan
```

For a mixed `AND`, equality terms may still narrow the candidate set. Any ordered/range term is then evaluated only against authoritative decrypted primary records. This preserves the benefit of the accepted equality index without persisting order-revealing range state.

The Rust planner enforces this by retaining only `CompareOp::Equal` index candidates for encrypted boxes before persisted index lookup.

## Correctness evidence

PR3 adds `rust/tests/encrypted_range_decision.rs` to lock the decision as behavior:

1. all five ordered/range operators are executed before and after an encrypted index is created and must produce identical results;
2. a mixed `AND` with encrypted equality + range indexes must remain semantically identical to the scan baseline;
3. the equality term may narrow candidates, while the range term remains authoritative predicate evaluation rather than persisted range lookup.

Existing PR2 coverage remains active for encrypted equality index create/backfill/mutation/reopen and range fallback.

## Performance policy

This is a security/complexity decision, not a claim that scanning is faster.

`make benchmark-query-index` remains the diagnostic query/index timing surface. Hosted-runner timing must not become a hard performance gate, and no performance number should be quoted unless produced by the corresponding benchmark run with methodology/toolchain context.

If encrypted range workloads later become a demonstrated production bottleneck, a future milestone may reopen this decision with a concrete leakage budget and benchmark evidence.

## Compatibility impact

PR3 intentionally introduces:

- no public Dart API change;
- no FRB shape change;
- no primary storage-format change;
- no change to `format_version = dxtr_box/1`;
- no fourth native profile;
- no new cryptographic dependency.

Existing encrypted equality index entries remain unchanged. Existing encrypted range queries continue to return the same results through scan fallback.

## Revisit criteria

Encrypted persisted range indexing should only be reconsidered if all of the following are true:

1. real workloads show encrypted range scans are a material bottleneck;
2. a specific representation has an explicit and acceptable leakage model;
3. correctness remains based on authoritative primary decrypt/authenticate + predicate recheck;
4. durable compatibility/versioning is defined;
5. dependency and native-size impact stays within policy or is deliberately accepted;
6. representative benchmarks demonstrate enough value to justify the complexity.

Until then, **scan-only encrypted range execution is the production contract**.
