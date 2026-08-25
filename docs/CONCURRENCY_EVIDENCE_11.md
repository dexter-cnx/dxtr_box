# dxtr_box 1.1 Concurrency Evidence

## Scope

This document records the 1.1 PR2 reliability/concurrency investigation. The goal is to strengthen executable evidence without changing the stable 1.0 public API, package identities, native profiles, or `dxtr_box/1` durable format.

## Existing baseline

Before this PR, native Rust coverage already proved:

- `DxtrBox` and `BoxHandle` are `Send + Sync`;
- one shared `BoxHandle` can accept concurrent mutations from multiple threads;
- multiple handles keep the underlying box open until the last handle closes;
- encrypted reopen behavior remains correct under the encryption profile.

These tests already establish that the native Rust facade is designed for ordinary multi-threaded use.

## Additional PR2 evidence

PR2 adds two regression cases to `rust/tests/rust_native_profiles_concurrency.rs`.

### Independent concurrent readers + writer

Three independently acquired handles to the same box are exercised concurrently:

- one writer repeatedly overwrites a shared key and inserts uniquely keyed records;
- two readers continuously read a stable seed record and the shared record;
- readers may observe any committed shared value, but never malformed data;
- final state must contain the writer's last committed shared value and the expected record count.

This validates concurrent visibility through independent native handles without introducing a cache or new synchronization API.

### Close + reopen durability after concurrent mutations

Two independent handles write disjoint key ranges concurrently, then both handles are closed. A newly reopened handle must observe the full committed record set and representative values from both writers.

This explicitly couples concurrency correctness to the existing durability/reopen contract.

## Dart isolate boundary

This PR does **not** claim Dart isolate support as a stable semantic contract.

The Rust engine and native handles have thread-safety evidence, but Dart isolates have a different runtime/FFI ownership model. A meaningful isolate claim requires an executable Flutter/Dart isolate harness that proves:

1. initialization behavior in more than one isolate;
2. independent FRB/native handles can open the same database safely;
3. committed writes become visible across isolates;
4. close/reopen behavior is deterministic;
5. watch/event semantics, if exercised, have an explicitly documented delivery model;
6. failure behavior does not rely on process-global Dart state accidentally shared by the test runner.

Until that harness exists and passes, documentation should say only that the native Rust layer is thread-safe under the tested conditions.

## Decision

No public API or storage change is justified by the current evidence.

The 1.1 reliability work should therefore remain test/evidence hardening. A Dart isolate API, process-level coordinator, or new synchronization abstraction should be considered only if a real consumer requirement appears and an executable reproduction demonstrates a gap.

## Preserved contract

```text
package = dxtr_box 1.0.0
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
flutter_rust_bridge = 2.8.0
redb = 2.1.0
durable format = dxtr_box/1
native profiles = minimal | encryption | full
```
