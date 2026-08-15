# dxtr_box Code Walkthrough

This walkthrough describes the current 0.1.x native foundation from the Flutter API down to redb, including native watch fan-out and persisted encrypted boxes.

## 1. Package boundary

```text
Flutter app
  -> Dart public API (DxtrBox / Box)
  -> NativeDxtrApi seam
  -> generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

The Dart layer owns API ergonomics, dynamic-value encoding, cached key metadata, and the public `BoxEvent` facade. Rust owns durable storage, transactions, encryption, handle lifetime, and native event fan-out.

## 2. Public entry point

`lib/dxtr_box.dart` exports the supported package API. Internal bridge, codec, and generated binding details stay under `lib/src/`.

```dart
await DxtrBox.init();
final box = await DxtrBox.open('settings');
await box.put('theme', 'dark');
final theme = await box.get('theme');
await box.close();
```

Encrypted boxes use the same public API:

```dart
final secure = await DxtrBox.open(
  'secrets',
  encryptionKey: 'correct horse battery staple',
);
```

Storage-backed reads are asynchronous by design. dxtr_box does not retain every value in the Dart heap to imitate Hive's synchronous in-memory model.

## 3. `DxtrBox`

File: `lib/src/dxtr_box.dart`

`DxtrBox` owns package-level lifecycle operations:

- `init()` resolves the database directory and initializes the native engine.
- `open()` validates the box name, opens the native box, registers a native watcher, then hydrates key metadata.
- `deleteBox()` removes a box file only when no native handles are live.
- `boxExists()` checks whether the corresponding `.dxtr` file exists.
- `bindNativeApi()` remains the test/alternate-engine seam.

Each open handle receives a random 128-bit watcher id. Watch registration happens before key hydration so startup mutations are either reflected in the refreshed metadata snapshot or delivered through the native stream.

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

Values stay in native storage.

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
  -> commit
  -> Rust emit NativeBoxEvent::Put
  -> FRB StreamSink
  -> every registered Box handle
  -> Dart metadata/event update
```

The public event is emitted only after a successful redb commit. Local Dart code does not emit a duplicate event.

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
  -> dynamic Dart value
```

A missing key returns `defaultValue`.

### `putAll`

Dart encodes all values first. Rust validates every MessagePack payload and prepares encrypted payloads before opening the redb write transaction. All entries are then inserted and committed atomically. One native `put` event is emitted per committed entry.

### `where`

The current `where()` is a linear client-side scan over persisted values. It is intentionally not the future indexed query engine.

### `watch`

`Box.watch()` is backed by Rust fan-out:

```text
WATCHERS
  box name
    -> watcher id A -> StreamSink
    -> watcher id B -> StreamSink
    -> ...
```

Mutations performed by any handle are delivered to every registered handle after commit. `watch(key:)` filters in Dart while still forwarding `clear`.

Failed sink sends are removed from the native watcher registry. `Box.close()` unregisters its watcher explicitly.

### Close path

```text
Box.close
  -> unregister native watcher
  -> cancel Dart native stream subscription
  -> NativeDxtrApi.closeBox
  -> decrement native handle refcount
  -> close public Dart event controller
```

Concurrent calls to `close()` share one in-flight Future.

## 5. Dynamic codec

File: `lib/src/codec.dart`

The Dart/Rust wire format is MessagePack. Supported values include:

- null
- bool
- int
- double
- String
- List
- `Map<String, dynamic>`
- `Uint8List`
- `DateTime`

DateTime and byte arrays use tagged representations. Maps reject non-string keys so the persisted format remains deterministic.

Rust validates MessagePack before values are accepted into storage. Application models are not deserialized in Rust.

## 6. Native seam and Flutter Rust Bridge

File: `lib/src/native_api.dart`

`NativeDxtrApi` prevents generated FRB symbols from leaking through the rest of the package. Unit tests can replace it with an in-memory fake, while production uses `FrbNativeDxtrApi`.

The production adapter initializes `RustLib` once, delegates lifecycle/CRUD calls, and maps generated native watch events into package-internal watch events.

Generated bindings live under `lib/src/rust/` and `rust/src/frb_generated.rs`. Native build ownership is the checked-in Cargokit package under `rust_builder/`.

## 7. Rust API boundary

File: `rust/src/api.rs`

Small lifecycle functions are `#[frb(sync)]`; value I/O remains asynchronous from Dart's perspective.

`open_box(name, encryption_key)` now forwards the optional key directly into `db::open`. The FRB signature did not change, so no binding regeneration was required for the encryption milestone.

Native watch registration uses FRB 2.8 `StreamSink<NativeBoxEvent>`. `put`, `put_all`, `delete`, and `clear` emit only after the storage function returns successfully.

For encrypted boxes, watch events still carry the original plaintext MessagePack bytes after commit. Encryption is a storage concern, not a public event-format change.

## 8. redb engine

File: `rust/src/db.rs`

Each box maps to one file:

```text
{base_path}/{box_name}.dxtr
```

Two redb tables are used:

```text
data: key -> stored value bytes
meta: storage format + encryption metadata
```

### Database cache and handles

Open databases are cached with per-box handle counts. Each cached entry also owns the resolved encryption state for that open box.

```text
OpenDatabase
  db: Arc<Database>
  handles: usize
  encryption: Arc<EncryptionState>
```

Opening a second handle to an already-open encrypted box must provide the same password. Rust derives a candidate key using the persisted salt and rejects mismatches before incrementing the handle count.

### Transactions

- `get`, `all_keys`, and `len` use read transactions.
- `put`, `put_all`, `delete`, and `clear` use write transactions.
- Writes become visible only after `commit()` succeeds.
- `put_all` validates and prepares all values before the write transaction, preventing partial writes caused by a later malformed value.

## 9. Persisted encryption

Files:

- `rust/src/crypto.rs`
- `rust/src/db.rs`
- `rust/Cargo.toml`

The standard native build now enables the `encryption` Cargo feature by default.

### Metadata contract

The `meta` table stores:

```text
format_version   = "dxtr_box/1"
encryption_mode  = "none" | "chacha20poly1305"
encryption_salt  = 16 random bytes          # encrypted boxes only
key_check         = encrypted sentinel       # encrypted boxes only
```

Each encrypted box gets a unique random salt. Argon2 derives a 32-byte key from the caller's password and that salt.

The key itself is never persisted. Instead, dxtr_box stores an encrypted known sentinel. Reopen derives the candidate key and decrypts/authenticates that sentinel. Missing or incorrect passwords fail before the box is registered as open.

### Value layout

`crypto::encrypt` generates a fresh 12-byte nonce for every value and stores:

```text
nonce || ChaCha20Poly1305 ciphertext+tag
```

On reads, authentication failure is returned as an error. Tampered ciphertext is never passed to the Dart codec.

### Plaintext compatibility

Boxes created before the metadata table existed are treated as known plaintext boxes. On normal reopen they receive explicit `dxtr_box/1` + `none` metadata.

Supplying an `encryptionKey` for an existing plaintext box is rejected. The project will add an explicit migration operation later rather than silently rewriting a box under a different storage contract.

Likewise, reopening an encrypted box without a key is rejected.

## 10. Why keys are cached but values are not

Hive-like APIs expect cheap `length`, `isEmpty`, and `keys`. Keeping only key metadata in Dart preserves those ergonomics without loading every stored value into RAM.

Same-isolate handles share key metadata, and native watch events keep it coherent when another handle mutates the box.

For extremely large key counts, a future native iterator/pagination API may replace full key caching.

## 11. Testing seams

```text
test/codec_test.dart
  Dart serialization

test/box_test.dart
  Box/DxtrBox semantics using FakeNativeDxtrApi
  native-watch fan-out/filtering/teardown semantics

test/native_integration_test.dart
  real Dart -> FRB -> Rust -> redb persistence
  real cross-handle native watch delivery
  encrypted close/reopen + wrong/missing-key rejection

rust/src/db.rs tests
  redb transactions
  handle lifecycle
  unique persisted salts
  encrypted on-disk payloads
  correct/wrong/missing password behavior
  tamper rejection
  plaintext/encrypted mode mismatch
```

Rust tests serialize mutations of process-global base-path/database state behind a test-only mutex.

CI also runs Rust fmt/clippy/tests on Ubuntu, macOS, and Windows plus the five-platform Flutter example build matrix.

## 12. Next architectural step

After persisted encryption is merged, the next storage/parity work is:

1. `deleteAll`
2. `compact()`
3. process-level crash/reopen durability testing
4. benchmark harness against `hive_ce`
5. explicit plaintext -> encrypted migration design
6. Cargo feature splitting before binary-size tuning
7. Dart 3.13 native tree-shaking / `record_use` hardening

The 1.0 functional-replacement claim remains gated by `docs/HIVE_FUNCTIONAL_PARITY.md`.
