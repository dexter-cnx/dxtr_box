# Dart Isolate / FRB Concurrency Evidence — 1.1

## Purpose

This evidence closes the gap left by the native Rust concurrency tests: whether independent Dart isolates can use the public `dxtr_box` API against the same database path through flutter_rust_bridge without sharing Dart `Box` objects or native handle wrappers across isolates.

## Executable evidence

`test/isolate_native_integration_test.dart` starts two independent Dart isolates. Each isolate:

1. calls `DxtrBox.init(path: ...)` independently;
2. opens the same box name through the public API;
3. commits an initial worker-specific record;
4. remains open while the peer isolate also has an open handle;
5. observes the peer's committed initial record through FRB/native storage;
6. writes the remainder of its own 32-record workload;
7. closes its own handle successfully before acknowledging completion.

The parent isolate waits for both completion acknowledgements, then initializes the same path, reopens the box, and verifies all 64 records and representative boundary values.

This is run by `.github/workflows/dart-isolate-concurrency.yml` with a release native library and `DXTR_BOX_NATIVE_TEST=1`.

## What this proves

- Dart isolates keep package static state independently and can initialize the same canonical database path separately.
- No `Box`, `SendPort`-unsafe native object, or FRB handle wrapper is transferred between isolates.
- Committed writes made through one isolate are visible through another independently opened isolate while both remain active.
- Independent isolate mutations remain durable after both worker handles close successfully and the database is reopened.
- The evidence exercises the public Dart API -> FRB -> shared Rust core -> redb path.

## What this does not claim

This is not a claim of lock-free execution, fairness, or deterministic scheduling. It does not introduce an isolate coordinator, shared Dart cache, cross-isolate watch contract, or new public API. It also does not imply that a `Box` instance itself is transferable between isolates.

If future work needs cross-isolate watch delivery, cancellation semantics, or stronger ordering guarantees, those require separate executable evidence and explicit contract decisions.

## Compatibility

No storage-format, public API, query, encryption, native profile, SDK-floor, or package-version change is required. The stable durable format remains `dxtr_box/1`.
