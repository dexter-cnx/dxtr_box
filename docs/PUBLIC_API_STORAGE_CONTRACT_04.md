# PH-05 Public API and Storage Contract Guard

Status: complete in PR #31.

## Goal

Make changes to the consumer-visible Dart boundary and durable on-disk format explicit in review before 1.0.

This milestone does **not** declare the 0.x API or storage format stable. It adds a fail-fast guard so an accidental export/signature removal or storage-format identity change cannot silently pass the normal test suite.

## Public Dart boundary

The package entrypoint remains `package:dxtr_box/dxtr_box.dart` with the current export set:

```text
src/box.dart
src/box_event.dart
src/dxtr_box.dart show DxtrBox
src/hive_ce_migration.dart
src/query.dart
```

`test/public_api_contract_test.dart` compiles representative constructors, enums, typedefs, query/index types, migration types, and typed `Box` method/getter tear-offs. A removal or incompatible signature change therefore fails analysis/test compilation.

`tool/verify_public_storage_contract.dart` also checks the entrypoint export set exactly. Adding or removing an export requires an intentional contract update in the same reviewed change.

The guard is intentionally narrower than hashing implementation files. Internal refactors that preserve the consumer contract must remain possible.

## Durable storage identity

The current redb metadata contract is:

```text
meta key: format_version
value:    dxtr_box/1
```

The verifier reads `rust/src/db.rs` and requires those identities to remain explicit.

A future storage-format change must not simply edit the constant to make CI green. The same change must define:

1. whether old boxes are readable directly;
2. whether an explicit migration is required;
3. failure/rollback semantics;
4. encryption/index compatibility;
5. tests opening data written under the previous format;
6. documentation and release notes for the compatibility boundary.

## CI behavior

The contract is part of the normal Flutter test suite. The standalone diagnostic command is:

```bash
dart run tool/verify_public_storage_contract.dart
```

Expected success marker:

```text
DXTR_BOX_CONTRACT PASS exports=5 storage=dxtr_box/1
```

No separate hosted-service dependency or code generator is introduced.

## Change policy before 1.0

0.x may still make deliberate breaking changes, but they must be visible. When the public contract changes:

- update the contract test/verifier intentionally;
- update README, handoff, and code walkthrough;
- explain migration/replacement guidance when an existing application would need changes;
- keep minimum Dart/Flutter compatibility unless a separately reviewed milestone changes it.

When the storage contract changes, backward-compatibility evidence is mandatory rather than advisory.

## Completion evidence

PH-05 closed in PR #31 after the public API compile contract, export-set verifier, and durable `format_version = dxtr_box/1` guard passed the normal CI matrix, including the minimum Flutter 3.22.0 / Dart 3.4.0 job and all five staged published-consumer platform builds.

## Non-goals

PH-05 does not:

- freeze every implementation detail;
- promise semantic-version stability before 1.0;
- change redb layout or runtime behavior;
- add a new Rust capability profile;
- reopen query/index or migration optimizations;
- replace the FRB drift, package, native-size, or staged-consumer gates.
