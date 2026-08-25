# 1.0 Public API Semantic Regression Inventory

This document records the consumer-visible behavior that must remain stable while `dxtr_box` moves from the completed 0.10 milestone toward 1.0.

The goal is not to freeze implementation details. It is to make compatibility-sensitive behavior explicit and executable.

## Scope

PR2 covers Dart-facing semantics that are already public and relied on by consumers:

- declarative query model construction and validation;
- fluent query AST compilation;
- logical grouping and mixed AND/OR associativity;
- sort, null-order, limit, and offset semantics;
- snapshot/immutability behavior of query groups and sort lists;
- existing public method/type signatures already covered by `test/public_api_contract_test.dart`;
- package/native/storage identity guards already covered by `tool/verify_public_storage_contract.dart`.

This PR does not add query features, change storage layout, change native profiles, or redesign the Dart API.

## Frozen semantic inventory

| Area | 1.0 compatibility expectation | Regression coverage |
| --- | --- | --- |
| `QueryComparison` | field/operator/value/upperValue remain observable and `between` requires an upper bound | `public_api_semantic_regression_test.dart` |
| dotted field validation | empty/invalid dotted paths remain rejected at construction time | `public_api_semantic_regression_test.dart` |
| `QueryGroup` | groups require at least one filter and retain an immutable snapshot | `public_api_semantic_regression_test.dart` |
| `BoxQuery` | sort list is snapshotted; limit must be > 0; offset must be >= 0 | `public_api_semantic_regression_test.dart` |
| `IndexDefinition` | identifier and field validation remain constructor-time behavior | `public_api_semantic_regression_test.dart` |
| mixed fluent AND/OR | chains remain left-associative | `public_api_semantic_regression_test.dart` |
| explicit fluent groups | `andGroup`/`orGroup` preserve explicit nested AST grouping | `public_api_semantic_regression_test.dart` |
| group modifiers | result modifiers remain invalid inside explicit predicate groups | `public_api_semantic_regression_test.dart` |
| fluent sorting | sort insertion order, ascending default, nulls-last default, descending/null override remain stable | `public_api_semantic_regression_test.dart` |
| fluent pagination | offset/limit propagate to `BoxQuery` and reject invalid values | `public_api_semantic_regression_test.dart` |
| public signatures | `Box`, `DxtrBox`, migration helpers, value/query types remain compile-time compatible | `public_api_contract_test.dart` |
| package/native/storage identity | package name, SDK floors, FRB/redb pins, Rust crate/root exports, `dxtr_box/1` remain guarded | `verify_public_storage_contract.dart` |

## Compatibility policy

A change to any row above is a 1.0 compatibility decision, not an incidental refactor. The same reviewed change must either:

1. preserve the behavior and update tests only when coverage was incomplete; or
2. explicitly document why compatibility is intentionally changing and update the release-readiness contract before merge.

Internal implementation changes remain allowed when these observable semantics stay unchanged.

## Remaining 1.0 work after PR2

- PR3 — release-candidate published-consumer, migration, and upgrade evidence;
- PR4 — final release audit, documentation sync, and `1.0.0` version closure.
