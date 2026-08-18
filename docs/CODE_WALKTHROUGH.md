# dxtr_box Code Walkthrough

This walkthrough describes the current publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution paths, and the completed 0.7 Query Ergonomics API surface.

## 1. Package boundary

```text
dxtr_box/
  lib/                 Dart API + generated FRB bindings
  rust/                Rust crate/library: rust_lib_dxtr_box
  cargokit/            native build integration
  android/
  ios/
  macos/
  linux/
  windows/
  example/
```

Stable compatibility:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
format_version = dxtr_box/1
```

## 2. Runtime ownership

```text
Flutter app
  -> BoxStore / Box / query + migration types
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lifecycle guards, query objects/builders, optional typed field metadata, and migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance, and plaintext-to-encrypted migration.

`DxtrBox` remains only as a deprecated compatibility facade over `BoxStore`.

## 3. Naming boundary after 0.7

Ordinary API/domain symbols use functional names:

```text
Box
BoxStore
BoxCodec
BoxQuery
BoxQueryBuilder
BoxField<T>
NativeBoxApi
FrbNativeBoxApi
UnavailableNativeBoxApi
BoxStoreMigrationInternals
```

Compatibility/package identities intentionally keep the product string:

```text
dxtr_box
rust_lib_dxtr_box
.dxtr
dxtr_box/1
@dxtr:* durable wire tags
```

The deprecated `DxtrBox`, `DxtrCodec`, and old native seam names exist only for source compatibility where required.

## 4. Storage and mutation atomicity

Each box maps to `{base_path}/{box_name}.dxtr`.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

Mutation path:

```text
Box.put / putAll / delete / deleteAll / clear
  -> BoxCodec
  -> NativeBoxApi
  -> FRB
  -> Rust validation
  -> optional encryption
  -> one redb write transaction
  -> primary + derived index changes
  -> commit
  -> watch event after commit only
```

Primary data is authoritative. Persisted indexes are derived state.

## 5. Point-read path

Public Dart API remains asynchronous:

```text
Box.get
  -> NativeBoxApi.get : Future<Uint8List?>
  -> FrbNativeBoxApi.get
  -> generated FRB sync dispatch
  -> Rust api::get #[frb(sync)]
  -> db::get
  -> fresh redb read transaction
  -> optional ChaCha20Poly1305 authenticate/decrypt
  -> MessagePack validation
  -> Dart decode
```

`Box.containsKey` uses the same small generated sync-dispatch optimization internally.

Only tiny single-key reads use this FRB call mode. Queries, batch reads, mutations, scans, and migrations remain asynchronous.

0.5 controlled boundary evidence retained:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

No Dart whole-box cache or long-lived stale read snapshot was introduced.

## 6. Batch-read path

```text
Box.getAll
  -> validate requested keys
  -> one asynchronous FRB crossing
  -> Rust api::get_all / db::get_all
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative key lookups
  -> decrypt/authenticate each encrypted hit
  -> MessagePack validation
  -> one response
  -> Dart decode per hit
```

Semantics:

```text
hit order: preserved
missing keys: omitted
duplicate input keys: duplicate output entries
```

## 7. Direct query execution

```text
Box.query(BoxQuery)
  -> serialize query AST
  -> one asynchronous FRB call
  -> one redb ReadTransaction snapshot
  -> optional persisted-index candidate narrowing
  -> authoritative primary reads
  -> optional decrypt/authenticate
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

Persisted indexes narrow candidates only. They do not replace predicate re-evaluation and do not currently satisfy ORDER BY.

## 8. 0.7 fluent string-path authoring

PR #44 introduced `BoxQueryBuilder` and collision-free `box.queryWhere(...)`:

```dart
final query = box
    .queryWhere('status').equals('active')
    .and('profile.age').gte(18)
    .build();

final rows = await box.query(query);
```

Supported comparisons map one-to-one to existing `QueryOperator` values:

```text
equals / notEquals
gt / gte / lt / lte
between
isNull / isNotNull
```

Boolean composition:

```text
and / or
andGroup / orGroup
```

Mixed `AND` / `OR` chaining is left-associative. Explicit groups produce the corresponding nested `QueryGroup` structure.

`Box.where(bool Function(dynamic))` remains the legacy predicate-scan API. Dart cannot overload methods, so the fluent entry point intentionally uses `queryWhere` rather than weakening or breaking source typing.

## 9. 0.7 result/sort/pagination ergonomics

PR #45 added result options directly onto the same builder:

```dart
final rows = await box
    .queryWhere('status').equals('active')
    .orderBy('name')
    .offset(10)
    .limit(20)
    .find();
```

The builder flow is:

```text
box.queryWhere(field)
  -> bound comparison stage
  -> BoxQueryBuilder state
  -> orderBy / offset / limit
  -> build()
  -> existing BoxQuery
  -> find()
  -> existing Box.query(build())
```

Standalone `BoxQueryBuilder.where(...)` remains a pure AST builder and intentionally has no `find()` because no `Box` execution context exists.

`findFirst`, `exists`, and `count` remain deferred until efficient native operations exist.

## 10. 0.7 optional typed field metadata

PR #46 added `BoxField<T>`:

```dart
const status = BoxField<String>('status');
const age = BoxField<int>('profile.age');
const name = BoxField<String>('name');
```

Typed bound execution:

```dart
final rows = await box
    .queryWhereField(status).equals('active')
    .andField(age).gte(18)
    .orderByField(name)
    .limit(20)
    .find();
```

Typed standalone composition:

```dart
final query = status
    .where().equals('active')
    .andField(age).gte(18)
    .orderByField(name)
    .build();
```

Explicit groups may use `whereField`, `andField`, and `orField`.

`BoxField<T>` is metadata only. It does not define a schema, generate serializers, create indexes, use reflection, or change storage. Typed stages delegate to the existing string-path builder and therefore produce the same `BoxQuery` / `QueryFilter` AST.

String paths remain first-class and may be mixed with typed metadata.

## 11. Query API equivalence

All supported authoring paths converge before serialization:

```text
manual BoxQuery -------------------------┐
                                        |
BoxQueryBuilder.where(String) -----------+--> BoxQuery / QueryFilter
                                        |
box.queryWhere(String) ------------------+
                                        |
BoxField<T>.where() ---------------------+
                                        |
box.queryWhereField(BoxField<T>) --------┘
                                                |
                                                v
                                      existing serialization / FRB
                                                |
                                                v
                                      existing Rust planner/indexes
```

No fluent or typed path may introduce semantics unavailable through direct `BoxQuery` construction.

## 12. Plaintext index execution

Plaintext indexes persist sortable scalar representations and may narrow:

```text
equal
>
>=
<
<=
between
```

Planner selection is deterministic. Multiple usable AND candidates may be intersected. Primary records are still authoritative and predicates are re-evaluated after candidate lookup.

## 13. Encrypted equality-index execution

Under `full`, encrypted equality candidate narrowing uses domain-separated keyed BLAKE2b MAC tokens:

```text
encrypted equality query
  -> canonical scalar value
  -> keyed BLAKE2b token
  -> exact token candidate lookup
  -> authoritative encrypted primary read
  -> ChaCha20Poly1305 authenticate/decrypt
  -> full predicate recheck
```

Encrypted index entries do not persist raw plaintext scalar bytes.

Accepted leakage includes equality classes/frequency, index/field metadata, and candidate record identifiers.

## 14. Encrypted ordered/range predicates

Encrypted persisted index tokens are not order-preserving. Therefore:

```text
Equal                  -> equality index may narrow
GreaterThan            -> scan
GreaterThanOrEqual     -> scan
LessThan               -> scan
LessThanOrEqual        -> scan
Between                -> scan
```

Mixed AND predicates may use an equality term to narrow candidates; range terms are then evaluated against authoritative decrypted records.

## 15. Migration path

Plaintext-to-encrypted migration and Hive CE migration preserve destination exclusivity and transactional writes.

`BoxStoreMigrationInternals` is the current functional migration seam. Old brand-prefixed migration internals should not be introduced into new code.

## 16. Native profiles

Exactly three profiles exist:

```text
minimal
encryption
full
```

`full` is default. Do not add a fourth profile.

## 17. Package and platform validation

The full merge quality bar validates:

```text
format + analyze
Dart tests
Flutter 3.22 / Dart 3.4 minimum SDK
Rust minimal/encryption/full
native integration
migration/query/index/crash-reopen regression
FRB generated bindings
native-size policy
package/pub dry-run
benchmark correctness smoke
Android consumer
Linux consumer
Windows consumer
macOS consumer
iOS consumer
```

## 18. Next architecture boundary

0.8 starts only after 0.7 closure merges to clean `main`.

Target dependency direction:

```text
Dart API ----> FRB adapter ----┐
                              ├----> shared authoritative Rust core ----> redb
Rust API ---------------------┘
```

The Rust frontend must not wrap Dart or FRB. GPUI is a potential external consumer only, not a dependency of Dxtr_Box.

See `docs/PROJECT_HANDOFF.md` for the guarded 0.8 audit and PR plan.
