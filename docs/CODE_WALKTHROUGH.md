# dxtr_box Code Walkthrough

This walkthrough describes the current 0.1.x native foundation from the Flutter API down to redb, including native watch fan-out, persisted encryption, explicit plaintext -> encrypted migration, bulk deletion, compaction, crash durability, native feature profiles, binary-size baselines, and the benchmark seam.

## 1. Package boundary

```text
Flutter app
  -> Dart public API (DxtrBox / Box)
  -> NativeDxtrApi seam
  -> optional NativeEncryptionMigrationApi maintenance capability
  -> generated flutter_rust_bridge bindings
  -> Rust API functions
  -> redb storage engine
```

The Dart layer owns API ergonomics, dynamic-value encoding, cached key metadata, lifecycle guards, and the public `BoxEvent` facade. Rust owns durable storage, transactions, encryption, handle lifetime, native event fan-out, migration, and storage maintenance operations.

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

Existing plaintext boxes are never reinterpreted as encrypted during `open()`. Migration is explicit:

```dart
await box.close();
await DxtrBox.encryptBox(
  'settings',
  encryptionKey: 'correct horse battery staple',
);
```

Storage-backed reads are asynchronous by design. dxtr_box does not retain every value in the Dart heap to imitate Hive's synchronous in-memory model.

## 3. `DxtrBox`

File: `lib/src/dxtr_box.dart`

`DxtrBox` owns package-level lifecycle operations:

- `init()` resolves the database directory and initializes the native engine.
- `open()` validates the box name, opens the native box, registers a native watcher, then hydrates key metadata.
- `deleteBox()` removes a box file only when no Dart handles are live.
- `encryptBox()` explicitly converts a closed plaintext box to encrypted storage.
- `boxExists()` checks whether the corresponding `.dxtr` file exists.
- `bindNativeApi()` remains the test/alternate-engine seam.

`encryptBox()` performs early Dart guards before crossing FFI:

```text
initialized?
  -> valid box name?
  -> non-empty encryption key?
  -> no live Dart handles for this name?
  -> configured engine implements NativeEncryptionMigrationApi?
  -> native migration
  -> clear cached key metadata for the closed box
```

The native layer repeats the critical persisted-state checks and remains the authority for storage correctness.

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

### `deleteAll`

`Box.deleteAll()` validates and de-duplicates the requested keys before crossing the native boundary.

```text
Box.deleteAll(keys)
  -> validate + de-duplicate keys in Dart
  -> NativeDxtrApi.deleteAll
  -> FRB
  -> api::delete_all
  -> db::delete_all
  -> one redb write transaction
  -> commit
  -> return only keys that actually existed
  -> Rust emits one delete event per removed key
  -> Dart shared key metadata removes committed deletions
```

Missing keys do not produce synthetic delete events.

### `compact`

`Box.compact()` is an explicit maintenance call:

```text
Box.compact
  -> NativeDxtrApi.compact
  -> FRB
  -> api::compact
  -> db::compact
  -> temporarily remove box from normal open registry
  -> redb compaction
  -> restore open database state
  -> bool result back to Dart
```

Access that races with compaction fails explicitly rather than silently using a stale handle. dxtr_box does not currently auto-compact on close or according to a size threshold.

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

`NativeDxtrApi` prevents generated FRB symbols from leaking through the rest of the package. Unit tests and alternate engines can implement the normal lifecycle/CRUD/watch seam without claiming they can rewrite encrypted storage.

Migration is separated as `NativeEncryptionMigrationApi`. Production `FrbNativeDxtrApi` implements both interfaces. This keeps encryption migration an explicit optional maintenance capability while preserving a clean primary test seam.

Generated bindings live under `lib/src/rust/` and `rust/src/frb_generated.rs`. CI regenerates them with `flutter_rust_bridge_codegen 2.8.0` and fails if committed generated files drift from `rust/src/api.rs`.

Native build ownership is the checked-in Cargokit package under `rust_builder/`.

## 7. Rust API boundary

File: `rust/src/api.rs`

Small lifecycle and maintenance functions are exposed through FRB; value I/O remains asynchronous from Dart's perspective.

`open_box(name, encryption_key)` forwards the optional key into `db::open`.

`encrypt_box(name, encryption_key)` takes the existing per-box mutation lock and delegates to `db::encrypt_box`, preventing in-process races with other mutation/maintenance paths.

Native watch registration uses FRB 2.8 `StreamSink<NativeBoxEvent>`. `put`, `put_all`, `delete`, `delete_all`, and `clear` emit only after the storage function returns successfully.

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

### Database cache and maintenance state

Open databases are cached with per-box handle counts and resolved encryption state:

```text
OpenDatabase
  db: Arc<Database>
  handles: usize
  encryption: Arc<EncryptionState>
```

Separate maintenance sets track compaction and migration so normal open/delete/access paths can reject conflicts explicitly.

### Transactions

- `get`, `all_keys`, and `len` use read transactions.
- `put`, `put_all`, `delete`, `delete_all`, and `clear` use write transactions.
- writes become visible only after `commit()` succeeds.
- `put_all` validates and prepares all values before the write transaction.
- `delete_all` performs requested removals in one write transaction and returns only existing keys actually removed.

## 9. Persisted encryption

Files:

- `rust/src/crypto.rs`
- `rust/src/db.rs`
- `rust/Cargo.toml`

The standard native build uses the `full` Cargo profile by default. Reduced `minimal` and `encryption` profiles are validated separately in CI without changing the public Dart SDK floor.

### Metadata contract

```text
format_version   = "dxtr_box/1"
encryption_mode  = "none" | "chacha20poly1305"
encryption_salt  = 16 random bytes          # encrypted boxes only
key_check         = encrypted sentinel       # encrypted boxes only
```

Each encrypted box gets a unique random salt. Argon2 derives a 32-byte key from the caller's password and that salt. The key itself is never persisted.

### Value layout

Encryption uses a fresh 12-byte nonce for every value and stores authenticated ChaCha20Poly1305 ciphertext. Record keys are used as AAD for stored values so swapping encrypted payloads between keys is rejected.

On reads, authentication failure is returned as an error. Tampered ciphertext is never passed to the Dart codec.

### Plaintext compatibility

Boxes created before the metadata table existed are treated as known plaintext boxes. On normal reopen they receive explicit `dxtr_box/1` + `none` metadata.

Supplying an `encryptionKey` for an existing plaintext box is rejected. The only supported transition is the explicit migration API.

## 10. Plaintext -> encrypted migration

Files:

- `lib/src/dxtr_box.dart`
- `lib/src/native_api.dart`
- `rust/src/api.rs`
- `rust/src/db.rs`
- `docs/PLAINTEXT_ENCRYPTION_MIGRATION.md`

Migration requires the box to be closed in the current process. Rust opens the persisted file for maintenance, verifies plaintext state, derives a new key from a fresh salt, validates every stored MessagePack payload, encrypts every value with a fresh nonce and record-key AAD, then updates the encryption metadata.

The value rewrites and final encryption metadata transition share one redb write transaction:

```text
before commit
  data = plaintext
  encryption_mode = none

single redb write transaction
  validate all values
  encrypt all values
  replace stored payloads
  set mode = chacha20poly1305
  persist salt + key_check
  commit

after successful return
  data = authenticated ciphertext
  encryption_mode = chacha20poly1305
```

If validation/encryption/redb work fails before commit, the transaction is not committed and the original plaintext state remains readable. Already-encrypted, missing, open, unsupported-format, or empty-key cases are rejected.

Migration does not emit `BoxEvent`s because live box handles are forbidden during the maintenance operation.

## 11. Crash durability and benchmarks

`rust/tests/process_crash.rs` kills a writer process after acknowledged commits and verifies a fresh process can reopen committed plaintext data in `minimal`; `encryption` and `full` additionally verify committed encrypted data. The project makes no durability claim for an operation that had not returned successfully before termination.

The separate `benchmark/` package compares equal logical workloads against current Hive CE without raising the root package's Dart/Flutter compatibility floor. Shared-runner timing is informational; CI checks harness execution, not performance thresholds.

## 12. Testing seams

```text
test/codec_test.dart
  Dart serialization

test/box_test.dart
  Box/DxtrBox semantics using FakeNativeDxtrApi
  native-watch fan-out/filtering/teardown semantics
  deleteAll and compact facade behavior

test/native_integration_test.dart
  real Dart -> FRB -> Rust -> redb persistence
  encrypted close/reopen + wrong/missing-key rejection
  public plaintext -> encrypted migration
  live-handle migration rejection
  post-migration data parity

rust/src/db.rs tests
  transactions + lifecycle
  compaction
  persisted encryption
  explicit migration success/rejection/failure safety

rust/tests/process_crash.rs
  acknowledged-commit process-kill recovery
```

CI also runs generated-FRB drift detection, Rust fmt/clippy plus minimal/encryption/full profile tests on Ubuntu/macOS/Windows, the minimum Flutter 3.22/Dart 3.4 lane, and a Linux x86_64 native-size job that records a baseline and repeats each profile three times to verify same-commit reproducibility.

## 13. Developer entry points

The root `Makefile` centralizes the normal developer path:

```text
make preflight
make frb-generate
make native-test
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

`make native-size-baseline` builds all three release profiles in isolated Cargo target directories and records exact artifact bytes plus environment/toolchain metadata in `build/native-size/native-size-baseline.tsv`.

## 14. Native feature profiles and next architectural step

PR #12 establishes three product-relevant profiles:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance (compact + plaintext migration)
```

The validated Linux x86_64 release-library baseline is 1,893,736 bytes for minimal, 1,992,296 bytes for encryption, and 2,032,312 bytes for full. PR #13 CI #151 repeated each profile three times with zero-byte spread, proving the harness is deterministic on that commit/toolchain. These measurements remain informational and platform-specific.

The active sequence after PR #12 is:

1. begin 0.3 query/index work while preserving the three-profile contract;
2. design any cross-commit binary-size regression budget separately from the now-validated same-commit stability gate;
3. keep the size artifacts machine-readable so future policy can compare controlled baselines;
4. before 1.0 RC, execute the full Hive Functional Parity Audit and close every practical `Gap`.

Dart 3.13 recorded-use/native tree shaking remains future-only and must not raise the Dart 3.4 / Flutter 3.22 compatibility floor. See `docs/FUTURE_NATIVE_TREE_SHAKING.md`.
