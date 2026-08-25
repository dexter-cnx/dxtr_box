# dxtr_box Code Walkthrough

This walkthrough describes the **1.1** architecture: one authoritative Rust/redb engine with a Flutter/Dart frontend through flutter_rust_bridge and a first-class native Rust frontend.

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

Stable contract:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
format_version = dxtr_box/1
package version = 1.1.0
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

### Dart point-read boundary

The generated FRB point helpers for `get`, `containsKey`, and `boxExists` are synchronous. Their Dart adapter methods keep the public asynchronous contract with `Future.sync`, so synchronous native throws are captured into the returned future instead of escaping before a future exists.

```text
Box.get
  -> NativeBoxApi.get
  -> Future.sync(generated FRB get)
  -> Uint8List payload
  -> BoxCodec.decode
```

The adapter intentionally does not re-copy a payload that already arrives as a full-buffer `Uint8List`. A sliced/view-backed `Uint8List` is normalized before MessagePack deserialization so its visible byte range remains authoritative.

### Dart batch/query read boundary

`getAll` and `query` keep the FRB/native batch calls asynchronous. This avoids converting potentially longer native operations into synchronous UI-thread work merely to improve microbenchmark numbers.

```text
Box.getAll
  -> NativeBatchReadApi.getAll
  -> generated FRB getAll
  -> NativeBatchRecord payloads
  -> BoxCodec.decode for each value
  -> fixed-length List<MapEntry<String, dynamic>>

Box.query
  -> build canonical query wire map
  -> BoxCodec.encode query payload
  -> NativeQueryApi.scanQuery
  -> generated FRB scanQuery
  -> BoxCodec.decode result payloads
  -> fixed-length List<MapEntry<String, dynamic>>
```

The production adapter returns FRB-owned payload lists directly for batch/query records; it does not duplicate each byte payload. `watchBox` remains different: event payloads are copied intentionally because watch delivery has a longer-lived ownership/lifetime boundary.

## 4. Codec and read-path performance evidence

`BoxCodec` is the stable Dart-side wire codec around MessagePack plus dxtr-specific tagged values.

```text
encode(value)
  -> _toWire(value)
  -> msgpack.serialize(...)
  -> Uint8List (returned directly; no second copy)

decode(bytes)
  -> normalize byte-view boundary when required
  -> msgpack.deserialize(...)
  -> _fromWire(...)
```

Read-path optimization is evidence-driven. The benchmark matrix separates:

```text
Rust core
-> generated FRB
-> Dart native adapter
-> public Dart API
```

The current diagnostics establish these decisions:

- fixed async/FRB overhead is material for small reads, so synchronous generated helpers are wrapped only where their native operation is already synchronous;
- duplicate adapter payload copies were removed from `getAll` and `scanQuery`;
- fixed-length public result construction is used for `getAll` and query results;
- query request wire building/encoding is small relative to the native query operation and is not the current optimization target;
- for a representative 100-record batch decode, MessagePack deserialization accounts for the majority of codec time, while tagged `_fromWire` conversion is still a meaningful minority;
- explicit-loop `_fromWire` map construction measured only a small improvement over the current comprehension shape, so production map conversion remains unchanged;
- `msgpack_dart 1.0.1` already returns `Uint8List` from `serialize`, so `BoxCodec.encode` now returns that buffer directly instead of cloning it through `Uint8List.fromList`;
- CI retains a codec encode-copy diagnostic so the direct-return decision has same-run evidence alongside the existing read-path decomposition;
- the MessagePack deserialize-shape diagnostic compares flat maps, nested maps, list-heavy values, string-heavy values, and byte-heavy values, recording both `ns/op` and `ns/byte` so future codec decisions can distinguish payload-size cost from structural parsing cost without changing `dxtr_box/1`.

Hosted absolute timings are diagnostic and noisy. Same-run layer ratios and component decomposition are the primary evidence used to justify a production optimization. Codec-library replacement or wire-layout changes require separate compatibility evidence; this diagnostic does not authorize a storage-format change.

## 5. Queries and indexes

```text
Dart BoxQuery/BoxQueryBuilder ----┐
                                  ├-> canonical QuerySpec -> planner -> redb
Rust QueryBuilder ----------------┘
```

Persisted indexes narrow candidates only; authoritative primary records are still read and predicates rechecked. Encrypted equality narrowing uses keyed tokens under `full`; encrypted ordered/range predicates remain scan-backed.

Exactly three profiles remain: `minimal`, `encryption`, and `full`. `full` is default.

## 6. Compatibility, conformance, and concurrency evidence

0.8 established bidirectional same-file compatibility. 0.9 added reusable conformance tests for CRUD, overwrite, batch ordering/duplicates/misses, enumeration, deletion, clear, and index lifecycle behavior. 0.10 added deterministic real-world workload evidence through equivalent Dart/FRB and Rust-native fixtures.

1.0 added release-stability guards around those foundations:

- exact public Dart export boundary;
- exact Rust root exports and wildcard-exported symbol set;
- semantic regression coverage for query AST/builders;
- staged published-consumer compilation against the principal public API surfaces;
- durable reopen, encrypted reopen, migration lifecycle, FRB generation, profile, package, and platform-consumer evidence.

1.1 adds post-release evidence without changing the runtime contract:

- hosted-registry external-consumer verification infrastructure;
- native concurrent reader/writer overlap through independent handles;
- concurrent mutation durability after reopen;
- reproducible Linux/macOS native-size evaluation with retained lockfile/metadata;
- independent Dart isolate -> FRB -> Rust shared-storage visibility and close/reopen durability.

## 7. Dart isolate path

Each isolate owns its own Dart static state and calls `DxtrBox.init(path: ...)` / `DxtrBox.open(...)` independently. `Box` instances and native wrappers are not transferred between isolates.

```text
Dart isolate A -> public API -> FRB ----┐
                                        ├-> shared Rust core -> same redb database
Dart isolate B -> public API -> FRB ----┘
```

The 1.1 evidence harness proves committed peer-write visibility while both isolates remain active and only allows the parent to reopen after both worker handles close successfully. It does not define cross-isolate watch ordering, fairness, lock-free execution, or Box-transfer semantics.

## 8. Release/consumer paths

`tool/validate_published_consumer.dart` stages the package according to `.pubignore`, rejects repository-only leakage, generates a fresh Flutter host app, wires the staged package as a path dependency, compiles representative public APIs, then builds the target platform.

CI runs that staged path for Android, iOS, macOS, Linux, and Windows. A separate 1.1 registry-resolved workflow exists for validating an actually published hosted package; repository version metadata alone does not prove registry publication.

## 9. Durable upgrade boundary

1.1 keeps:

```text
meta[format_version] = dxtr_box/1
```

No 1.1 storage migration is introduced. Existing persistence/reopen, encrypted reopen, cross-frontend same-file, migration destination, crash-reopen, native concurrency, and Dart isolate tests remain executable compatibility evidence.

## 10. Merge quality bar

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
Dart isolate / FRB concurrency evidence
```

See `docs/RELEASE_AUDIT_110.md`, `docs/NATIVE_SIZE_DECISION_11.md`, `docs/DART_ISOLATE_CONCURRENCY_EVIDENCE_11.md`, and `docs/PROJECT_HANDOFF.md` for the 1.1 evidence boundary and maintenance rules.