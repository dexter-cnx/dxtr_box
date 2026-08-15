# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: a Hive-simple Flutter API backed by redb, with durable storage outside the Dart heap and no app-level model code generation.

## Current snapshot — 0.1.0 foundation

Implemented:

- Public Dart facade: `DxtrBox`, `Box`, `BoxEvent`.
- MessagePack wire codec for null/bool/int/double/String/List/Map<String,dynamic>/Uint8List/DateTime.
- Rust `redb = 2.1.0` engine with one `{box}.dxtr` file per box.
- Global `Lazy<RwLock<HashMap<String, Arc<Database>>>>` open-database cache.
- Transactional put, putAll, get, contains, delete, clear, keys, length, close, deleteBox, boxExists.
- Optional encryption primitives using Argon2 + ChaCha20Poly1305 behind Cargo feature `encryption`.
- Rust CRUD/codec tests and Dart codec tests.
- Five-platform package metadata plus local scaffold/bootstrap scripts.

## Deliberate API correction

The initial Hive-shaped proposal used synchronous `get()` / `containsKey()` / `values`. A redb-backed database does not keep every value in Dart RAM, so native storage reads should not block Flutter's UI isolate. The foundation therefore exposes storage reads asynchronously.

`length` and `keys` are cached metadata in the Dart `Box`; values are fetched from redb on demand.

## Current limitation

The checked-in Dart `NativeDxtrApi` is an explicit seam over generated Flutter Rust Bridge symbols. The generated FRB adapter and platform Cargokit/native integration are not yet checked in because this execution environment does not provide Flutter, Cargo, or `flutter_rust_bridge_codegen`.

On a Flutter/Rust workstation:

```bash
cargo install flutter_rust_bridge_codegen --version 2.8.0
./tool/scaffold_platforms.sh
./tool/bootstrap.sh
```

Then replace `UnavailableNativeDxtrApi` with the generated FRB adapter and initialize `RustLib` exactly once before the first database call.

## Next implementation sequence

1. Complete FRB adapter and make macOS 0.1.0 green first.
2. Run Android, iOS, Linux, and Windows compile/test matrix.
3. Add native Rust event broadcast + FRB stream for `watch()`; current Dart stream only observes writes through the same `Box` instance.
4. Implement persisted encryption metadata: format/version marker, unique random salt per encrypted box, key verification, encrypt/decrypt in the value path.
5. Add `deleteAll`, `compact()`, and benchmark harness against `hive_ce`.
6. Add crash/reopen ACID tests.
7. Split optional Rust functionality into Cargo features before binary-size tuning.
8. Add Dart 3.13 native tree-shaking hardening using build/link hooks and `package:record_use` where the FRB/native-symbol mapping permits it.
9. Add binary-size regression CI with separate measurements for minimal CRUD, CRUD+encryption, and full-feature builds.
10. Only after the storage/bridge path is stable, start 0.3 query/index work.

## Dart 3.13 native tree-shaking policy

Native tree-shaking is a production-hardening priority, not an MVP blocker. The intended order is:

`functional FRB/redb core -> Cargo feature splitting -> record_use/link-hook integration -> size measurement -> further symbol/linker tuning`.

Do not claim a `<1MB` binary until measured per target architecture and build mode. Track the minimal CRUD binary separately from encryption-enabled and full-feature variants.

## Security rule for 0.2 encryption

Never derive a key from a fixed global salt. Persist a unique random salt per encrypted box and derive a 32-byte key with Argon2id. Store nonce+ciphertext for each encrypted value. ChaCha20Poly1305 authentication failure must reject modified payloads and wrong keys.
