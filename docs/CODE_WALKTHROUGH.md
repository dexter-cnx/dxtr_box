# dxtr_box Code Walkthrough

This walkthrough describes the current dxtr_box architecture from the Flutter API down to redb, including lifecycle, native watch fan-out, persisted encryption, explicit plaintext -> encrypted migration, bulk mutation, compaction, query execution, persisted secondary-index maintenance, crash durability, native feature profiles, and the benchmark seam.

## 1. Package boundary

```text
Flutter app
  -> Dart public API (DxtrBox / Box / query types)
  -> NativeDxtrApi capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

The Dart layer owns API ergonomics, dynamic-value encoding/decoding, lightweight key metadata, lifecycle guards, and public events/query objects. Rust owns durable storage, transactions, encryption, handle lifetime, native event fan-out, migration, query evaluation, persisted index state, and maintenance operations.

## 2. Public entry point

`lib/dxtr_box.dart` exports the supported package API. Internal bridge, codec, and generated binding details stay under `lib/src/`.

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');
await box.put('theme', 'dark');
final theme = await box.get('theme');
await box.close();
```

Encrypted boxes use the same open API:

```dart
final secure = await DxtrBox.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);
```

Existing plaintext boxes are never reinterpreted as encrypted during `open()`. Migration is explicit through `DxtrBox.encryptBox(...)`.

Storage-backed reads are asynchronous by design. dxtr_box does not retain every value in the Dart heap to imitate Hive's synchronous in-memory model.

## 3. `DxtrBox`

File: `lib/src/dxtr_box.dart`

`DxtrBox` owns package-level lifecycle operations:

- `init()` resolves the database directory and initializes the native engine.
- `open()` validates the box name, opens native storage, registers a watcher, then hydrates lightweight key metadata.
- `deleteBox()` removes a box file only when no Dart handles are live.
- `encryptBox()` explicitly converts a closed plaintext box to encrypted storage.
- `boxExists()` checks whether the corresponding `.dxtr` file exists.
- `bindNativeApi()` remains the test/alternate-engine seam.

`lazy: true` is rejected until a distinct lazy-box contract exists. Normal values are already read on demand from Rust/redb.

## 4. `Box`

File: `lib/src/box.dart`

A `Box` keeps only lightweight Dart-side state:

```text
name
shared key metadata
native watcher id/subscription
closed/closing state
public BoxEvent controller
```

Values remain in native storage.

### Plain write path

```text
Box.put
  -> DxtrCodec.encode
  -> NativeDxtrApi.put
  -> FRB
  -> api::put
  -> db::put
  -> MessagePack validation
  -> optional value encryption
  -> redb write transaction
  -> persisted-index maintenance when full profile has definitions
  -> commit
  -> Rust emit NativeBoxEvent::Put
  -> FRB StreamSink
  -> every registered Box handle
```

Primary data mutation and persisted-index mutation share the same redb write transaction. Public events are emitted only after a successful commit.

### Read path

```text
Box.get
  -> NativeDxtrApi.get
  -> FRB
  -> api::get
  -> db::get
  -> redb read transaction
  -> optional AEAD decrypt/authenticate
  -> MessagePack validation
  -> bytes back through FRB
  -> DxtrCodec.decode
```

A missing key returns `defaultValue`.

### Bulk mutation

`putAll()` validates/encodes all values before committing primary records and any derived index changes atomically.

`deleteAll()` de-duplicates requested keys, removes existing keys in one redb write transaction, maintains indexes in that transaction, and emits delete events only for keys actually removed.

`clear()` removes primary records and clears persisted index entries in the same committed storage transition.

### `compact`

`Box.compact()` is explicit maintenance. Native code temporarily takes the box out of the normal open-database registry while redb compaction runs. Racing access fails explicitly rather than silently using a stale handle.

### Legacy `where`

`Box.where(bool Function(dynamic))` remains the Dart-side compatibility/diagnostic linear scan. It is not the declarative native query engine.

### `watch`

Native watcher registry:

```text
WATCHERS
  box name
    -> watcher id A -> StreamSink
    -> watcher id B -> StreamSink
```

Mutations performed by any handle are delivered to every registered handle after commit. `watch(key:)` filters in Dart while still forwarding `clear`. Failed sink sends are pruned from the native watcher registry.

### Close path

```text
Box.close
  -> unregister native watcher
  -> cancel Dart stream subscription
  -> NativeDxtrApi.closeBox
  -> decrement native handle refcount
  -> close public event controller
```

Concurrent `close()` calls share one in-flight future.

## 5. Dynamic codec

File: `lib/src/codec.dart`

The Dart/Rust wire format is MessagePack. Supported values include null, bool, int, double, String, List, `Map<String, dynamic>`, `Uint8List`, and `DateTime`.

DateTime and byte arrays use tagged representations. Maps reject non-string keys. Rust validates MessagePack before storage. Application models are not deserialized as typed Rust models.

## 6. Native capability seams and FRB

File: `lib/src/native_api.dart`

The production adapter `FrbNativeDxtrApi` implements the core seam plus optional capabilities used by the Dart facade.

Important capability interfaces include:

```text
NativeDxtrApi
NativeEncryptionMigrationApi
NativeQueryApi
NativeIndexApi
```

This lets tests/alternate engines implement only the capabilities they actually support. Dart checks optional capabilities explicitly and returns a clear unsupported error rather than assuming every backend has query/index or migration support.

Generated bindings live under `lib/src/rust/` and `rust/src/frb_generated.rs`. CI regenerates them with `flutter_rust_bridge_codegen 2.8.0` and fails on drift. Native build ownership belongs to the checked-in Cargokit package under `rust_builder/`.

## 7. Declarative query path

Public query types live in `lib/src/query.dart`:

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup
QueryOperator
QueryLogicalOperator
IndexDefinition
```

Typical call shape:

```dart
final rows = await box.query(
  BoxQuery(
    where: QueryGroup.and([
      QueryComparison(
        field: 'profile.age',
        operator: QueryOperator.greaterThanOrEqual,
        value: 18,
      ),
      QueryComparison(
        field: 'status',
        operator: QueryOperator.equal,
        value: 'active',
      ),
    ]),
    limit: 20,
  ),
);
```

Execution path:

```text
Box.query
  -> serialize BoxQuery AST to tagged MessagePack via DxtrCodec
  -> NativeQueryApi.scanQuery
  -> one FRB call for the whole query
  -> api::scan_query
  -> query::decode_query once
  -> enumerate committed native records
  -> decrypt record when box is encrypted
  -> decode MessagePack value
  -> nested dotted-field lookup
  -> evaluate comparisons + AND/OR groups
  -> deterministic record-key ordering
  -> apply offset/limit
  -> return matching key + payload records in one FRB response
  -> Dart decode payloads
```

Supported comparison operators currently include equality/inequality, numeric/string ordering, `between`, `isNull`, and `isNotNull`.

The public contract is **one FRB call per query**, not one FFI call per record. Internally the first scan executor still enumerates keys and reads records individually rather than keeping a single redb read transaction for the entire scan. That internal transaction shape is a future optimization; semantics must not change.

Encrypted boxes use this same scan path. Decrypted values exist only inside the trusted native execution path before results are returned through the normal plaintext API contract.

## 8. Persisted secondary indexes

Files:

- `rust/src/index.rs`
- `rust/src/db.rs`
- `rust/src/api.rs`

The first persisted-index foundation is full-profile only.

redb tables:

```text
index_definitions: index name -> dotted field path
index_entries: encoded composite entry -> derived record reference
```

Index entry keys use a length-aware binary composite representation rather than delimiter concatenation.

Dart facade:

```dart
await box.createIndex(
  const IndexDefinition(name: 'by-status', field: 'status'),
);
final indexes = await box.listIndexes();
final removed = await box.dropIndex('by-status');
```

### Create/backfill

```text
Box.createIndex
  -> NativeIndexApi.createIndex
  -> FRB
  -> api::create_index
  -> index::create
  -> validate name + dotted field path
  -> reject encrypted box
  -> scan current primary DATA
  -> derive scalar entries
  -> one redb write transaction:
       persist definition
       persist derived entries
  -> commit
```

### Transactional maintenance

When persisted definitions exist, primary mutations call index maintenance inside the same redb write transaction:

```text
put / putAll
  -> remove old derived entry when needed
  -> add new derived entry
  -> primary DATA update
  -> one commit

delete / deleteAll
  -> remove derived entry
  -> remove primary DATA
  -> one commit

clear
  -> clear primary DATA
  -> clear derived entries
  -> one commit
```

Primary records remain authoritative. Indexes are always derived state.

### Encryption policy

Persisted index creation is intentionally rejected for encrypted boxes because storing plaintext-derived scalar keys would leak protected fields. Encrypted boxes can still use native scan queries.

Plaintext -> encrypted migration is also rejected while persisted index definitions exist. An encrypted persisted-index representation must be designed before that transition can be supported safely.

### Planner status

Persisted indexes are **not used by the query planner yet**. There is no planner-enabled fast path in PR #14. Native scan remains authoritative.

The next query/index milestone is:

```text
eligible predicate
  -> planner chooses index or scan
  -> identical logical results
  -> identical deterministic ordering/pagination
  -> exhaustive equivalence tests
```

## 9. Rust API boundary

File: `rust/src/api.rs`

FRB-exposed functions stay small. Important query/index functions are:

```text
scan_query(box_name, query_payload)
create_index(box_name, name, field)
list_indexes(box_name)
drop_index(box_name, name)
```

Reduced profiles retain a stable public native surface and return explicit errors for full-only query/index operations.

Mutation APIs emit native watch events only after storage returns successfully.

## 10. redb engine

File: `rust/src/db.rs`

Each box maps to one file:

```text
{base_path}/{box_name}.dxtr
```

Core tables:

```text
data: key -> stored value bytes
meta: storage format + encryption metadata
```

Full-profile query/index adds the two derived index tables described above.

Open databases are cached with handle counts and resolved encryption state. Separate maintenance state prevents incompatible compaction/migration/open operations from racing silently.

Reads use redb read transactions. Mutations use write transactions and become visible only after `commit()` succeeds.

## 11. Persisted encryption

Files:

- `rust/src/crypto.rs`
- `rust/src/db.rs`

Metadata:

```text
format_version   = "dxtr_box/1"
encryption_mode  = "none" | "chacha20poly1305"
encryption_salt  = unique random bytes
encrypted key_check sentinel
```

Each encrypted box gets a unique salt. Argon2 derives a 32-byte key. ChaCha20Poly1305 encrypts each stored value with a fresh nonce, using the record key as AAD so ciphertext swapping between keys is rejected.

Authentication failure is returned as an error before bytes reach the Dart codec.

## 12. Plaintext -> encrypted migration

Migration requires the box to be closed. Rust validates plaintext state, derives a fresh key/salt, validates every MessagePack payload, encrypts every value, and changes data + encryption metadata in one redb write transaction.

With persisted index definitions present, migration is currently rejected. This avoids leaving plaintext-derived persisted indexes beside newly encrypted primary data.

Durable states remain binary: fully plaintext before commit, fully encrypted after commit.

## 13. Crash durability and benchmarks

`rust/tests/process_crash.rs` verifies acknowledged commits survive abrupt process termination and reopen. No claim is made for operations that had not returned successfully before process termination.

The separate `benchmark/` package compares equal logical workloads against Hive CE without raising the root package SDK floor. Shared-runner timing is informational; CI checks harness execution, not absolute performance thresholds.

## 14. Testing seams

```text
test/query_test.dart
  public query AST + validation

test/box_test.dart
  Box/DxtrBox semantics via fake native APIs
  optional query/index capability facade behavior

test/native_integration_test.dart
  real Dart -> FRB -> Rust -> redb persistence/encryption/migration

rust/tests/query_index.rs
  native scan semantics
  persisted index lifecycle/reopen
  encrypted scan + encrypted-index rejection

rust/tests/process_crash.rs
  acknowledged-commit process-kill recovery
```

CI also runs generated-FRB drift detection, Rust fmt/clippy plus minimal/encryption/full profile tests on Ubuntu/macOS/Windows, the minimum Flutter 3.22/Dart 3.4 lane, a Linux native FRB round trip, Linux x86_64 same-commit native-size reproducibility, and Android/iOS/macOS/Linux/Windows example builds.

## 15. Developer entry points

The root `Makefile` centralizes the normal developer path:

```text
make preflight
make frb-generate
make native-test
make query-index-test
make process-crash
make benchmark-smoke
make benchmark-full
make rust-check
make native-build-minimal
make native-build-encryption
make native-size-baseline
make native-size-stability
make example-android
make example-linux
make example-windows
make example-macos
make example-ios
```

## 16. Native profiles and next architectural step

The project keeps exactly three public native profiles:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

`full` remains the default Cargokit/Flutter production build. Query/index implementation may use internal optional dependencies such as `rmpv` without creating another public product profile.

The next 0.3 architectural step is planner/index-backed query execution with comprehensive scan/index equivalence coverage. Cross-commit binary-size policy and Dart 3.13 native tree shaking remain separate future work and must not block query/index correctness.
