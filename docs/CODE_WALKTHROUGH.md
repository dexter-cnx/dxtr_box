# dxtr_box Code Walkthrough

This walkthrough describes the current **0.9** architecture: one authoritative Rust/redb storage engine with a Flutter/Dart frontend through flutter_rust_bridge and a first-class native Rust frontend.

## 1. Package boundary

```text
dxtr_box/
  lib/                 Dart API + generated FRB bindings
  rust/                Rust crate/library: rust_lib_dxtr_box
  cargokit/            native build integration
  android/ ios/ macos/ linux/ windows/
  example/             Flutter consumer
```

Stable compatibility contract:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
format_version = dxtr_box/1
package version = 0.9.0-dev.1
```

## 2. Dependency direction

```text
Dart API -> FRB adapter ----┐
                            ├-> shared Rust core -> redb
Rust API -------------------┘
```

The native Rust frontend does not call Dart or FRB. Both frontends enter the same core for lifecycle, storage, encryption, query/index, and maintenance behavior.

Main Rust boundaries:

```text
rust/src/api.rs       FRB-facing adapter functions and bridge DTOs
rust/src/native.rs    native Rust facade: DxtrBox / BoxHandle / query builder
rust/src/core.rs      shared authoritative engine operations
rust/src/db.rs        redb/storage mechanics
rust/src/query.rs     canonical query representation/evaluation
rust/src/index*.rs    persisted index implementation
rust/src/error.rs     structured Rust-facing DxtrBoxError
```

`rust_lib_dxtr_box` builds as both `cdylib` for Flutter and `rlib` for native Rust consumers.

## 3. Durable ownership

Each box maps to `{base_path}/{box_name}.dxtr` with:

```text
meta[format_version] = dxtr_box/1
```

There is no Dart storage format and no Rust-native storage format. MessagePack values and all durable metadata remain shared.

Primary data is authoritative. Persisted indexes are derived state maintained transactionally with primary mutations.

## 4. Dart mutation path

```text
Box.put / putAll / delete / deleteAll / clear
  -> BoxCodec
  -> NativeBoxApi
  -> generated FRB
  -> rust/src/api.rs
  -> shared core
  -> optional encryption
  -> one redb write transaction
  -> primary + derived index changes
  -> commit
  -> watch event after commit only
```

Dart owns public async ergonomics, MessagePack encode/decode, lifecycle guards, query authoring objects, optional `BoxField<T>` metadata, and Hive CE migration preflight.

## 5. Native Rust mutation path

```text
DxtrBox::open
  -> shared core init

DxtrBox::box_
  -> shared core open_box

BoxHandle::put / put_all / delete / delete_all / clear
  -> shared core
  -> same redb mutation path as FRB adapter
```

`BoxHandle` closes its shared runtime handle explicitly through `close()` and defensively on `Drop`.

Rust callers receive `Result<T, DxtrBoxError>` instead of FRB's string-flattened bridge errors.

## 6. Point and batch reads

Dart/FRB point read:

```text
Box.get
  -> FrbNativeBoxApi.get
  -> generated FRB sync dispatch
  -> api::get
  -> shared core get
  -> redb read transaction
  -> optional authenticate/decrypt
  -> MessagePack validation
  -> Dart decode
```

Rust-native point read:

```text
BoxHandle::get
  -> shared core get
  -> same redb/authentication/validation path
  -> Vec<u8> MessagePack bytes to Rust caller
```

Batch reads converge on one core operation:

```text
getAll / get_all
  -> validate keys
  -> shared core get_all
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative key lookups
  -> authenticate/decrypt each encrypted hit
  -> validate MessagePack
  -> ordered hit records
```

Semantics are shared: hit order is preserved, misses are omitted, and duplicate input keys produce duplicate output entries.

No Dart whole-box cache or long-lived stale read snapshot is used.

## 7. Query execution

Dart authoring:

```text
BoxQuery / BoxQueryBuilder / BoxField<T>
  -> canonical query wire representation
  -> FRB adapter
  -> canonical Rust QuerySpec
```

Rust-native authoring:

```text
BoxHandle::query()
  -> QueryBuilder
  -> canonical Rust QuerySpec
```

Both converge before execution:

```text
QuerySpec
  -> planner/index selection
  -> one redb read snapshot
  -> authoritative primary reads
  -> optional decrypt/authenticate
  -> full predicate recheck
  -> deterministic semantic sort
  -> offset / limit
```

There is no second Rust-native query engine. Persisted indexes narrow candidates only and do not currently satisfy ORDER BY.

## 8. Persisted indexes and encryption

Plaintext persisted indexes may narrow equality and range predicates.

Under `full`, encrypted equality narrowing uses domain-separated keyed BLAKE2b MAC tokens. Raw plaintext scalar values and semantic ordering are not persisted in encrypted index entries.

Encrypted ordered/range predicates remain scan-backed. Authoritative decrypt/authenticate and predicate recheck remain mandatory after candidate narrowing.

## 9. Native profiles

Exactly three profiles remain:

```text
minimal     CRUD/lifecycle/watch-capable core
encryption  minimal + encrypted box support
full        encryption + maintenance + query/index implementation
```

`full` is default. Query/index Rust APIs that require `full` are feature-gated rather than creating another profile.

## 10. Cross-frontend compatibility and conformance

0.8 durable compatibility tests prove both directions:

```text
Rust-native put -> close -> FRB adapter open/get
FRB adapter put -> close -> Rust-native open/get
```

0.9 adds a reusable `StorageBoxContract` test kit that runs the same semantic assertions against both frontends. It covers missing-key behavior, CRUD, overwrite, bulk put, `get_all` ordering/duplicates/misses, key enumeration, delete/delete-all, clear, and final empty state.

0.9 also adds index lifecycle guards across Rust-native and FRB-adapter paths so startup work cannot silently introduce schema registration or alter dynamic create/drop/reopen semantics.

## 11. Configuration fingerprint decision

0.9 intentionally does **not** persist a schema/index fingerprint.

The persisted `index_definitions` table is already the authoritative configuration and there is no independent consumer-supplied desired schema manifest at open time. Startup performs no expensive schema reconciliation/rebuild pass for a fingerprint to skip, so a second durable hash would duplicate state without a meaningful correctness discriminator.

A future fingerprint is justified only if there is an independent expected configuration plus a measured reconciliation cost worth skipping.

## 12. Startup/reopen path and benchmark

The startup diagnostic runs through the public Rust-native facade and measures repeated open/reopen behavior against prepared boxes.

Run:

```bash
bash tool/startup_benchmark.sh
```

Matrix:

```text
records = 0 | 1,000 | 10,000
indexes = 0 | 1 | 4
```

Each case emits:

```text
first_open_us
reopen_p50_us
reopen_p95_us
reopen_max_us
```

Hosted Linux x64 evidence showed reopen p95 remaining below 1 ms across the matrix with no material growth at 10,000 records and 4 persisted indexes. Therefore 0.9 introduces no startup fast path, no startup cache, and no persisted fingerprint metadata.

Benchmark safety:

- zero iterations are rejected;
- a caller-provided startup root is treated only as a parent directory;
- the benchmark removes only its dedicated `dxtr-box-startup-benchmark` child.

## 13. Multi-frontend benchmark path

`bash tool/multi_frontend_benchmark.sh` executes equivalent logical workloads for:

```text
rust-native public facade
Dart public API -> generated FRB
```

Workloads:

```text
point get
100-key get_all / getAll
indexed equality query + descending sort + limit(50)
```

Evidence output:

```text
build/multi-frontend/rust-native.jsonl
build/multi-frontend/dart-frb.jsonl
build/multi-frontend/startup-open.jsonl
```

Treat the measurements as diagnostic evidence rather than marketing speedup claims.

## 14. Flutter-facing ergonomics remain intact

String-path fluent authoring remains first-class:

```dart
final rows = await box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

Optional typed metadata remains only an authoring layer:

```dart
const status = BoxField<String>('status');
final rows = await box.queryWhereField(status).equals('active').find();
```

Both compile to the existing canonical query representation and retain the same planner semantics.

## 15. Package and merge validation

The full merge quality bar retains:

```text
format + analyze
Dart tests
Flutter 3.22 / Dart 3.4 minimum SDK
Rust minimal/encryption/full all-target tests
native integration
migration/query/index/crash-reopen regression
FRB generated binding reproducibility
native-size policy
package/pub dry-run
benchmark correctness/smoke
Android/Linux/Windows/macOS/iOS staged consumers
```

0.9 adds reusable cross-frontend conformance and reproducible startup evidence without weakening any existing gate.

## 16. 0.9 boundary

0.9 closes with a conservative evidence-backed outcome: improve semantic conformance and startup observability, but do not add speculative runtime state.

It does not add GPUI integration, Tokio, ORM/schema/model generation, cloud sync/networking, storage-format redesign, a fourth native profile, or a new encryption/query engine.

See `docs/RELEASE_AUDIT_09.md` for closure evidence and `docs/PROJECT_HANDOFF.md` for the current project state.
