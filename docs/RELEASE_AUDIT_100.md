# dxtr_box 1.0.0 Release Audit

## Release decision

`dxtr_box` 1.0.0 freezes the existing public/package/durable contracts after the 0.10 evidence milestone and the 1.0 stabilization sequence. It does not introduce a new storage format, query engine, encryption design, runtime cache, GPUI dependency, Tokio commitment, ORM/codegen layer, sync layer, or fourth native profile.

## Frozen identities

```text
package = dxtr_box
version = 1.0.0
Rust package/lib = rust_lib_dxtr_box
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
format_version = dxtr_box/1
```

## 1.0 stabilization evidence

### PR1 — contract freeze

Executable guards freeze the Dart export boundary, Rust root exports, wildcard-exported Rust API symbol set, Cargo package/lib identity, native crate type, exact dependency/profile requirements, and durable format markers.

### PR2 — semantic regression

Regression tests freeze query-model validation, immutable query snapshots, mixed AND/OR left associativity, explicit `andGroup`/`orGroup` AST semantics, sort/null ordering, and pagination validation.

### PR3 — release-candidate consumer / upgrade evidence

The staged publish payload is consumed by generated Flutter host apps on Android, iOS, macOS, Linux, and Windows. The consumer smoke compiles principal Dart public surfaces rather than only importing the package.

Existing executable durability evidence remains authoritative for upgrade safety:

- plaintext persistence across close/reopen;
- encrypted persistence and correct-key reopen;
- missing/wrong encryption-key rejection;
- cross-frontend same-file compatibility;
- migration destination reservation and lifecycle cleanup;
- process crash/reopen regression coverage;
- dynamic index lifecycle/reopen coverage.

Because the durable marker remains `dxtr_box/1`, 1.0 requires no storage migration.

## Required merge gates

Before merging the 1.0 release PR, all applicable CI jobs must be green:

- format / analyze / Dart tests;
- Flutter 3.22.0 / Dart 3.4.0 minimum compatibility;
- public/storage contract verifier;
- semantic regression suite;
- Rust `minimal`, `encryption`, and `full` profiles;
- native integration;
- migration/query/index/crash-reopen regression;
- generated FRB reproducibility;
- native-size stability/regression policy;
- package documentation and `dart pub publish --dry-run`;
- benchmark correctness/smoke;
- staged published consumers on Android/iOS/macOS/Linux/Windows.

## Post-1.0 compatibility policy

After release, changes to public Dart semantics, Rust root API, package/native identities, native profiles, encryption/storage semantics, or `dxtr_box/1` must be treated as compatibility-sensitive. Any breaking change requires an explicit versioning and migration decision.
