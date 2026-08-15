# dxtr_box Code Walkthrough

This walkthrough describes the 0.1.0 foundation from the public Flutter API down to the redb transaction layer.

## 1. Package boundary

The package is intentionally split into three layers:

```text
Flutter app
  -> Dart public API (DxtrBox / Box)
  -> NativeDxtrApi seam / generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

The Dart layer owns API ergonomics, dynamic-value encoding, cached key metadata, and local box events. Rust owns durable storage and transactions. The application does not generate model adapters or serializers.

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
- `open()` validates the box name, opens the redb file, creates a `Box`, then hydrates its key metadata.
- `deleteBox()` removes a box file through Rust.
- `boxExists()` checks whether the corresponding `.dxtr` file exists.
- `bindNativeApi()` is the seam used by generated FRB bindings and tests.

A box name may not be empty, `.` or `..`, and may not contain path separators. The same validation exists in Rust so callers cannot bypass the Dart guard through native APIs.

## 4. `Box`

File: `lib/src/box.dart`

`Box` is the Hive-shaped object used by application code.

It stores only lightweight metadata in Dart:

```text
name
keys
closed state
event controller
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
  -> update Dart key metadata
  -> emit BoxEvent
```

Metadata and events are updated only after the native write completes successfully.

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

Dart encodes every value before invoking native code. Rust validates every MessagePack payload before opening the redb write transaction, then inserts all entries in one transaction and commits once.

### `where`

The 0.1.0 `where()` API is intentionally a linear client-side scan. It reads each persisted value and applies the Dart predicate. It is not the planned 0.3 query engine and does not use indexes.

### `watch`

The current stream is local to a Dart `Box` instance. It observes mutations performed through that object. Cross-instance/native event broadcasting is scheduled for 0.2.0 via an FRB stream.

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

Rust's `codec.rs` validates incoming MessagePack before a transaction is written. Rust does not deserialize application models in the MVP; it stores opaque validated MessagePack bytes.

## 6. Native seam and Flutter Rust Bridge

File: `lib/src/native_api.dart`

`NativeDxtrApi` isolates the package API from generated FRB symbols. This gives two benefits:

1. Dart behavior can be unit-tested with an in-memory fake without loading a native library.
2. FRB-generated naming/layout changes remain contained in one adapter instead of leaking through `Box` and `DxtrBox`.

`UnavailableNativeDxtrApi` deliberately fails with a useful message until generated bindings are wired.

The production adapter should initialize `RustLib` once and implement `NativeDxtrApi` by delegating to the generated functions.

## 7. Rust API boundary

File: `rust/src/api.rs`

This module exposes functions for flutter_rust_bridge and immediately delegates storage work to `db.rs`.

Small lifecycle calls are currently marked `#[frb(sync)]`; value I/O functions are left asynchronous from Dart's perspective so disk work does not need to block Flutter's UI isolate.

Encryption keys are rejected in 0.1.0 even though cryptographic primitives already exist behind a Cargo feature. Persisted encryption metadata and value-path integration belong to 0.2.0.

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

### Database cache

Open databases are cached as:

```rust
Lazy<RwLock<HashMap<String, Arc<Database>>>>
```

The global lock protects only cache lookup/mutation. Each operation clones the `Arc<Database>` and releases the cache lock before starting a redb transaction, avoiding unnecessary serialization through the global map.

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

This is deliberately not connected to redb yet. 0.2.0 must add persisted box encryption metadata, key verification, decrypt-on-read, encrypt-on-write, and migration/version rules before the public `encryptionKey` option is considered implemented.

## 10. Why keys are cached but values are not

The Hive-like API expects cheap `length`, `isEmpty`, and `keys`. Keeping only keys in Dart provides those ergonomics without loading every stored value into RAM.

For very large key counts this still has a memory cost. A later API may expose native iterators/pagination, but the 0.1 contract intentionally prioritizes Hive-simple behavior while eliminating full-value box residency.

## 11. Testing seams

The suite is split by responsibility:

```text
test/codec_test.dart
  Dart dynamic-value serialization

test/box_test.dart
  Box/DxtrBox semantics using FakeNativeDxtrApi

rust/src/db.rs tests
  real redb files and transaction behavior
```

The Rust engine uses process-global state, so its unit tests take a test-only mutex before changing the base path/cache. This avoids parallel `cargo test` cases corrupting each other's assumptions.

See `docs/TESTING.md` for the full test matrix and CI gates.

## 12. Next architectural step

The next critical path remains:

```text
platform plugin scaffolds
  -> FRB code generation
  -> NativeDxtrApi production adapter
  -> macOS smoke test
  -> Android/iOS/Linux/Windows validation
```

Only after that path is green should 0.2.0 add encryption persistence, native watch streams, compaction, and benchmark work.
