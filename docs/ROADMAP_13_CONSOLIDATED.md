# v1.3 consolidated delivery: security, batch, query and feature evidence

Status: implementation checklist (not release evidence). This combines the previously proposed PRs 1–8 into one integration PR. Do not mark complete without executable evidence.

## Current baseline (1.2)
- `Box.getAll` / native `get_all`, `deleteAll`, fluent Dart `queryWhere`, Rust canonical planner, and persisted plaintext/encrypted indexes already exist. Extend rather than duplicate.
- `flutter analyze` already runs in minimum-SDK CI and `make ci-fast` is the mandatory fast gate. Verify coverage before adding another job.
- Three supported native profiles remain `minimal | encryption | full`. No new combination ships in 1.3 without a compatibility decision.
- Dart `DxtrBox` remains a deprecated shim until the planned 2.0 removal; Rust `DxtrBox` is an independent public native API and must not be removed by Dart cleanup.
- Durable format stays `dxtr_box/1`; FRB 2.8.0, redb 2.1.0 and minimum SDK contracts remain unchanged.

## Workstream A: Security documentation and tests (original PR1)
- [ ] Prominent README warning: deterministic encrypted equality-index tokens expose equality classes and frequency of repeated indexed values to an attacker with access to persisted index entries. They do not reveal plaintext directly, but low-cardinality/sensitive fields can enable inference when combined with auxiliary information.
- [ ] Document threat model, access assumptions, field-selection guidance, mitigation options (do not index sensitive low-cardinality fields; scan/decrypt instead where appropriate), and residual leakage.
- [ ] Document that encrypted range/ordered predicates scan and recheck authenticated primary records.
- [ ] Add deterministic-token/equality-leakage and wrong-key/reopen regression tests, ensuring no sensitive example data enters CI logs.
- [ ] Publish a 1.3 security/migration note explaining no storage-format migration and how to remove/rebuild an unsuitable index.

## Workstream B: CI security gates (original PR2)
- [ ] Add a mandatory, reproducible `cargo audit --locked --file rust/Cargo.lock` job with pinned tooling and an explicit reviewed advisory-exception policy; no blanket `|| true`.
- [ ] Confirm `flutter analyze` is a required gate for all Dart/public-API changes (it already runs in minimum-SDK CI); avoid redundant jobs.
- [ ] Keep format, Rust three-profile tests, Dart tests, cross-platform consumers and generated FRB binding checks intact.
- [ ] State explicitly that dependency audit/static analysis cannot detect equality leakage; require threat-model review and behavioral security tests.

## Workstream C: Boundary-efficient batch APIs (original PR3–5)
- [ ] Profile existing `getAll`/native `get_all` semantics and performance first. Add `getMany` only if it provides demonstrably different semantics or an intentional naming transition.
- [ ] Add `putMany`/native batch write using one Rust transaction and one FRB terminal call. Specify duplicate-key order, all-or-nothing atomicity, error handling, empty input, encrypted records and watch notifications.
- [ ] Preserve `getAll` ordering, missing-key and duplicate-key behavior. No N repeated FRB point calls behind a batch facade.
- [ ] Cross-frontend and crash/reopen tests for plaintext/encrypted batch reads and writes.
- [ ] Repeatable native-vs-Dart/FRB benchmarks: point get, batch sizes 1/10/100/1000, batch writes, cold/warm runs, indexed query, throughput and p50/p95. Record hardware, build mode and toolchain; do not market runner-specific numbers as general speedups.

## Workstream D: Query ergonomics and optimization (original PR6–7)
- [ ] Review `docs/FLUENT_BOX_QUERY_SPEC.md` and existing `queryWhere` builder; implement the approved `box.query().where(...).get()` surface without breaking the old API in 1.x.
- [ ] Immutable builder composition stays in Dart; one terminal FRB execution request. Reuse the authoritative Rust AST/planner.
- [ ] Parity tests for nested fields, comparisons, AND/OR precedence, sorting/tie-breaks, offset/limit, `count` and `exists`; index-vs-scan result equivalence.
- [ ] Query explain/requireIndex and cursor pagination only when the Phase A contract is stable; document any deferrals explicitly.
- [ ] Benchmark indexed and scan queries across native Rust and Dart/FRB, including encrypted equality and scan-backed range cases.

## Workstream E: Feature architecture evidence (original PR8)
- [ ] Measure size, dependencies and build times of existing three profiles across representative targets.
- [ ] Prototype `query` without `encryption` in an isolated branch/experiment if consumer need justifies it; verify feature unification, compilation, test matrix, binary savings and API gates.
- [ ] Record an explicit keep-three-profiles vs finer-grained-feature decision. Do not silently change supported profiles in 1.3. Any breaking public capability/profile changes require a versioned migration plan (target 2.0).

## Integrated merge gate
- [ ] All implemented code, tests, docs and generated bindings are committed; no checklist-only merge as a feature release.
- [ ] `make preflight`, mandatory audit/analyze, Rust profile matrix, migration/query/index tests, FRB reproducibility and applicable platform consumer checks pass.
- [ ] README, code walkthrough, handoff, benchmarks and release notes reflect **implemented** behavior only.
- [ ] Publish measured before/after results and security limitations; identify deferred items clearly.
- [ ] No Dart shim removal in 1.3; document exact 2.0 removal target and migration examples.
