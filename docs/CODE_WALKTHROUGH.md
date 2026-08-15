# dxtr_box Code Walkthrough

This walkthrough describes the current 0.1.x foundation from the public Flutter API down to redb, including the native watch path.

## 1. Package boundary

The package is intentionally split into three layers:

```text
Flutter app
  -> Dart public API (DxtrBox / Box)
  -> NativeDxtrApi seam / generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

The Dart layer owns API ergonomics, dynamic-value encoding, cached key metadata, and the public `BoxEvent` stream facade. Rust owns durable storage, transactions, and native event fan-out. The application does not generate model adapters or serializers.

## 2. Public entry point

`lib/dxtr_box.dart` exports the supported package API. Internal bridge and codec details remain under `lib/src/`.

Typical usage is:

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');
await box.put('theme', 'dark');
final theme = await box.get('theme');
await box.close();
```

Storage-backed reads are asynchronous by design. Unlike Hive's in-memory boxes, dxtr_box does not retain every value in the Dart heap.

## 3. `DxtrBox`

File: `lib/src/dxtr_box.dart`

`DxtrBox` owns package-level lifecycle operations:

- `init()` resolves the database directory and initializes the native engine.
- `open()` validates the box name, opens the redb file, registers a native watcher, then hydrates key metadata.
- `deleteBox()` removes a box file through Rust when no handles are live.
- `boxExists()` checks whether the corresponding `.dxtr` file exists.
- `bindNativeApi()` is the test/alternate-engine seam.

Each open handle receives a random 128-bit watcher id. Watch registration happens before key hydration so mutations that occur during startup are either included in the refreshed metadata snapshot or delivered by the native stream.

`lazy: true` is rejected until a distinct lazy-box contract is implemented. Normal reads already fetch values from native storage on demand rather than retaining full box contents in Dart RAM.

## 4. `Box`

File: `lib/src/box.dart`

`Box` is the Hive-shaped object used by application code.

It stores only lightweight state in Dart:

```text
name
shared key metadata
native watcher id/subscription
closed/closing state
public BoxEvent controller
```

Values stay in redb and are fetched on demand.

### Write path

For `put('age', 42)`:

```text
Box.put
  -> DxtrCodec.encode(42)
  -> NativeDxtrApi.put(box, key, bytes)
  -> FRB
  -> api::put
  -> db::put
  -> redb write transaction
  -> commit
  -> Rust emit NativeBoxEvent::Put
  -> FRB StreamSink
  -> every registered Box handle
  -> Dart metadata/event update
```

The initiating `Box` also updates its shared key metadata after the native call succeeds, so `keys`/`length` are immediately coherent after `await put(...)`. Public events are not emitted locally; they come only from the Rust stream, avoiding duplicate notifications.

### Read path

For `get('age')`:

```text
Box.get
  -> NativeDxtrApi.get(box, key)
  -> FRB
  -> api::get
  -> db::get
  -> redb read transaction
  -> Vec<u8>
  -> DxtrCodec.decode
  -> dynamic Dart value
```

A missing key returns `defaultValue`.

### `putAll`

Dart encodes every value before invoking native code. Rust validates every MessagePack payload before opening the redb write transaction, then inserts all entries in one transaction and commits once. After the commit, Rust emits one native `put` event per committed entry.

### `where`

The current `where()` API is intentionally a linear client-side scan. It reads each persisted value and applies the Dart predicate. It is not the planned query engine and does not use indexes.

### `watch`

`Box.watch()` is backed by native Rust fan-out.

```text
Rust WATCHERS
  box name
    -> watcher id A -> StreamSink
    -> watcher id B -> StreamSink
    -> ...
```

A mutation performed by any handle is emitted after the redb commit succeeds and is delivered to every registered handle for that box. `watch(key:)` filters by key in Dart but still forwards `clear`, preserving existing public semantics.

When a sink send fails, Rust removes that watcher entry. Normal `Box.close()` explicitly unregisters its watcher.

### Close path

```text
Box.close
  -> unregister watcher in Rust / drop StreamSink
  -> cancel Dart native stream subscription
  -> NativeDxtrApi.closeBox
  -> native handle refcount decrement
  -> close public BoxEvent controller
```

Concurrent calls to `close()` share one in-flight Future.

## 5. Dynamic codec

File: `lib/src/codec.dart`

The Dart/Rust wire format is MessagePack. Supported values are:

- null
- bool
- int
- double
- String
- List
- `Map<String, dynamic>`
- `Uint8List`
- `DateTime`

DateTime and byte arrays use tagged representations so their Dart types survive round trips. Maps reject non-string keys to keep the storage format deterministic and queryable later.

Rust's codec validation checks incoming MessagePack before a transaction is written. Rust does not deserialize application models in the MVP; it stores opaque validated MessagePack bytes.

## 6. Native seam and Flutter Rust Bridge

File: `lib/src/native_api.dart`

`NativeDxtrApi` isolates package logic from generated FRB symbols. This allows Dart behavior to be unit-tested with an in-memory fake and contains FRB-generated naming/layout changes in one adapter.

The production `FrbNativeDxtrApi` initializes `RustLib` once, delegates CRUD/lifecycle calls, and maps generated `NativeBoxEvent` values into the package-internal `NativeWatchEvent` representation.

Generated bindings are checked in under `lib/src/rust/` and `rust/src/frb_generated.rs`. Native build ownership belongs to the checked-in Cargokit package under `rust_builder/`; the root package does not own duplicate platform FFI scaffolds.

## 7. Rust API boundary

File: `rust/src/api.rs`

This module exposes functions for flutter_rust_bridge and delegates storage work to `db.rs`.

Small lifecycle calls are marked `#[frb(sync)]`; value I/O remains asynchronous from Dart's perspective.

Native watch registration uses FRB 2.8 `StreamSink<NativeBoxEvent>`. The watcher registry is keyed by box name and watcher id. `put`, `put_all`, `delete`, and `clear` emit only after the corresponding `db` function has returned successfully, so the event describes a committed mutation.

Encryption keys are still rejected until persisted encryption metadata and value-path integration are implemented.

## 8. redb engine

File: `rust/src/db.rs`

Each box maps to one file:

```text
{base_path}/{box_name}.dxtr
```

The engine uses:

```rust
TableDefinition<&str, &[u8]>
```

Keys are UTF-8 strings. Values are MessagePack byte slices.

### Database cache and handles

Open databases are cached with per-box handle counts. The global lock protects cache lookup/mutation only; operations clone the database handle and release the cache lock before starting redb work.

Closing one `Box` therefore does not invalidate another handle for the same box. `deleteBox` is rejected while live handles remain.

### Transactions

- `get`, `all_keys`, and `len` use read transactions.
- `put`, `put_all`, `delete`, and `clear` use write transactions.
- Writes become visible only after `commit()` succeeds.

`put_all` validates all payloads before starting its write, preventing a malformed later entry from leaving an earlier subset committed.

## 9. Encryption foundation

File: `rust/src/crypto.rs`

The optional `encryption` Cargo feature contains:

- random 16-byte salt generation
- Argon2 key derivation to 32 bytes
- ChaCha20Poly1305 authenticated encryption
- random 12-byte nonce per encrypted value
- nonce + ciphertext payload layout

This is deliberately not connected to redb yet. The next encryption milestone must add persisted box encryption metadata, key verification, decrypt-on-read, encrypt-on-write, and migration/version rules before the public `encryptionKey` option is considered implemented.

## 10. Why keys are cached but values are not

The Hive-like API expects cheap `length`, `isEmpty`, and `keys`. Keeping only keys in Dart provides those ergonomics without loading every stored value into RAM.

Multiple same-isolate handles share the same key metadata object. Native watch events also update that metadata, so changes from another handle remain coherent.

For very large key counts this still has a memory cost. A later API may expose native iterators/pagination.

## 11. Testing seams

The suite is split by responsibility:

```text
test/codec_test.dart
  Dart dynamic-value serialization

test/box_test.dart
  Box/DxtrBox semantics using FakeNativeDxtrApi
  native-watch fan-out / filtering / teardown semantics

test/native_integration_test.dart
  real Dart -> FRB -> Rust -> redb persistence
  real cross-handle native watch delivery

rust/src/db.rs tests
  real redb files and transaction behavior
```

The Rust engine uses process-global state, so its unit tests take a test-only mutex before changing the base path/cache.

See `docs/TESTING.md` for the full test matrix and CI gates.

## 12. Next architectural step

With lifecycle hardening, five-platform native builds, and native watch fan-out in place, the next storage milestone is persisted encryption metadata and value-path encryption. After that come batch deletion/compaction, crash/reopen durability testing, benchmark work, Cargo feature splitting, and Dart 3.13 native tree-shaking/size hardening.
