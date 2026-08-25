# Flutter single-key get experiment

This experiment isolates the Flutter/Dart overhead around the existing synchronous flutter_rust_bridge point-read entrypoint.

## Finding

The generated FRB `get_` binding and Rust `get` entrypoint are synchronous, while the production Dart adapter previously added an async state machine and repeated initialization await around every point read.

On hosted Linux x64, the isolated pre-change diagnostic measured median latency of approximately 22.1 us/op for public `Box.get`, 15.8 us/op for the async native adapter, 2.1 us/op for raw synchronous FRB `get_`, and 3.0 us/op for synchronous FRB plus MessagePack decode.

After removing the unnecessary async state machine from `FrbNativeBoxApi.get` while preserving its `Future<Uint8List?>` contract, a second diagnostic measured approximately 20.8 us/op for public `Box.get` and 12.2 us/op for the native adapter. Raw synchronous timing varied between hosted runners, so the result is interpreted by normalized boundary-overhead ratios rather than absolute cross-run latency.

The adapter/raw-sync ratio fell from about 7.38x to 5.17x, and the public-get/sync-plus-decode ratio fell from about 7.37x to 5.82x. This supports retaining the adapter optimization while keeping the public asynchronous API unchanged.

## Scope

The production change is intentionally narrow:

- preserve `Box.get` and `NativeBoxApi.get` public/internal Future contracts;
- invoke the already-synchronous generated FRB point read directly inside `FrbNativeBoxApi.get`;
- rely on the existing `BoxStore.init` / `openBox` lifecycle to initialize `RustLib` before point reads;
- introduce no Dart whole-box cache, storage-format change, Rust-core change, or API break.

The normal read-path, real-world, isolate-concurrency, benchmark-correctness, generated-binding, minimum-SDK, native-integration, Rust-profile, and five-platform consumer validation matrix remains authoritative for merge safety.
