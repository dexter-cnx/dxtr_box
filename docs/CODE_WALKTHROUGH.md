# dxtr_box Code Walkthrough

This walkthrough describes the **1.0** architecture: one authoritative Rust/redb engine with a Flutter/Dart frontend through flutter_rust_bridge and a first-class native Rust frontend.

## 1. Package and durable boundary

```text
dxtr_box/
  lib/                 Dart API + generated FRB bindings
  rust/                Rust crate/library: rust_lib_dxtr_box
  benchmark/           deterministic diagnostics and workload runners
  tool/                reproducible CI/local evidence scripts
  android/ ios/ macos/ linux/ windows/
  example/             Flutter consumer
```

Stable 1.0 contract:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
format_version = dxtr_box/1
package version = 1.0.0
```

Each box maps to `{base_path}/{box_name}.dxtr`. There is no Dart-only or Rust-only storage format.

## 2. Dependency direction

```text
Dart API -> FRB adapter ----┐
                            ├-> shared authoritative Rust core -> redb
Rust API -------------------┘
```

The native Rust frontend never calls Dart or FRB. GPUI is not a dependency of the core package.

Primary Rust boundaries:

```text
rust/src/api.rs       FRB-facing bridge adapter
rust/src/native.rs    native Rust facade
rust/src/core.rs      shared authoritative operations
rust/src/db.rs        redb/storage mechanics
rust/src/query.rs     canonical query representation/evaluation
rust/src/index*.rs    persisted index implementation
rust/src/error.rs     structured Rust errors
```

## 3. Mutation and read paths

Dart mutation path:

```text
Box.put / putAll / delete / deleteAll / clear
  -> BoxCodec
  -> NativeBoxApi
  -> generated FRB
  -> shared Rust core
  -> optional encryption
  -> one redb write transaction
  -> primary + derived index changes
  -> commit
  -> watch event after commit
```

Rust-native mutations enter the same shared Rust core. Point and batch reads use fresh authoritative redb read transactions. `getAll/get_all` preserves hit order, omits misses, and preserves duplicate input hits.

There is no Dart whole-box cache or long-lived stale read snapshot.

## 4. Queries and indexes

```text
Dart BoxQuery/BoxQueryBuilder ----┐
                                  ├-> canonical QuerySpec -> planner -> redb
Rust QueryBuilder ----------------┘
```

Persisted indexes narrow candidates only; authoritative primary records are still read and predicates rechecked. Encrypted equality narrowing uses keyed tokens under `full`; encrypted ordered/range predicates remain scan-backed.

Exactly three profiles remain: `minimal`, `encryption`, and `full`. `full` is default.

## 5. Compatibility and conformance

0.8 established bidirectional same-file compatibility. 0.9 added reusable conformance tests for CRUD, overwrite, batch ordering/duplicates/misses, enumeration, deletion, clear, and index lifecycle behavior. 0.10 added deterministic real-world workload evidence through equivalent Dart/FRB and Rust-native fixtures.

1.0 adds release-stability guards around those foundations:

- exact public Dart export boundary;
- exact Rust root exports and wildcard-exported symbol set;
- semantic regression coverage for query AST/builders;
- staged published-consumer compilation against the principal public API surfaces;
- durable reopen, encrypted reopen, migration lifecycle, FRB generation, profile, package, and platform-consumer evidence.

## 6. Release candidate consumer path

`tool/validate_published_consumer.dart` stages the package according to `.pubignore`, rejects repository-only leakage, generates a fresh Flutter host app, wires the staged package as a path dependency, compiles representative public APIs, then builds the target platform.

CI runs that path for Android, iOS, macOS, Linux, and Windows. This validates the publishable payload rather than only the repository checkout.

## 7. Durable upgrade boundary

The 1.0 release keeps:

```text
meta[format_version] = dxtr_box/1
```

No 1.0 storage migration is introduced. Existing persistence/reopen, encrypted reopen, cross-frontend same-file, migration destination, and crash-reopen tests remain the executable upgrade evidence.

## 8. Merge quality bar

Full validation covers:

```text
format + analyze
Dart tests
Flutter 3.22 / Dart 3.4 minimum SDK
Rust minimal/encryption/full tests
native integration
migration/query/index/crash-reopen regression
public contract + semantic regression guards
FRB generated bindings
native-size policy
package/pub dry-run
benchmark correctness/smoke
Android/Linux/Windows/macOS/iOS staged consumers
```

See `docs/RELEASE_AUDIT_100.md`, `docs/RELEASE_CANDIDATE_EVIDENCE_10.md`, and `docs/PROJECT_HANDOFF.md` for the release boundary and maintenance rules.
