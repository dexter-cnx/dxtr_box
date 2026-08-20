# 0.8 Rust-native profiles and concurrency contract

This document records the PR3 contract for the first-class Rust frontend introduced in 0.8.

## Native profiles

Dxtr_Box continues to expose exactly three native profiles:

```text
minimal
  -> CRUD, lifecycle, batch reads, key iteration

encryption
  -> minimal + encrypted create/open/reopen

full
  -> encryption + maintenance + persisted indexes + canonical query/sort/pagination
```

No Rust-specific fourth profile is introduced. The Rust frontend consumes the same crate features and the same `dxtr_box/1` storage as the Dart/FRB frontend.

`cargo test --all-targets` is intentionally exercised under all three feature selections by the existing `make rust-test-profiles` target. Rust-native tests and examples therefore participate in the same profile matrix as the rest of the engine.

## Capability behavior

Core CRUD is available in every profile.

In reduced profiles, persisted-index operations and native query execution return structured `DxtrBoxError::UnsupportedFeature` errors rather than silently changing semantics. These are the capability errors covered by the PR3 reduced-profile contract. Maintenance operations keep their existing shared-core error mapping in 0.8; PR3 does not redefine that error surface.

The encryption profile can create, close, and reopen encrypted boxes through the Rust frontend with the same key validation and authenticated storage path used by the shared core.

## Send / Sync contract

The public Rust-native `DxtrBox` and `BoxHandle` types are required to remain `Send + Sync`. PR3 includes compile-time assertions so an implementation change that removes either auto-trait fails the Rust integration suite.

This contract permits sharing a box handle between worker threads without introducing an async runtime dependency.

Dxtr_Box does **not** make a Tokio commitment in 0.8.

## Mutation concurrency

Same-box mutations from multiple threads share the authoritative core mutation lock:

```text
Rust thread A ----┐
Rust thread B ----┼----> per-box mutation lock ----> redb write transaction
Rust thread C ----┘
```

This preserves the existing transaction/index/watch ordering invariant. The Rust frontend does not add a second lock or bypass the shared core.

PR3 regression coverage performs concurrent writes through one shared `BoxHandle` and verifies the complete committed result set afterward.

## Handle ownership

Opening the same box multiple times increments the shared engine handle count. Closing or dropping one Rust-native handle must not invalidate another live handle. The database leaves the process registry only when the final handle is released.

PR3 adds explicit integration coverage for this ownership rule.

## Root binding

`DxtrBox` carries its own base path and rebinds the shared engine root before opening or inspecting a box. As established in PR2, switching roots while another root still has live boxes is rejected by the shared engine rather than producing cross-root access.

Applications should treat one active storage root per process as the current 0.8 operating model. Multi-root simultaneous access is not introduced by PR3.

## Native consumer example

`rust/examples/native_consumer.rs` is an external-consumer-style example that compiles under all three profiles. Under `full` it demonstrates:

```text
open -> put -> create index -> query -> sort -> limit -> close
```

Reduced profiles demonstrate the common CRUD surface without referencing full-only types.

## Preserved invariants

PR3 does not change:

- `dxtr_box/1`;
- redb 2.1.0;
- flutter_rust_bridge 2.8.0;
- the canonical query engine;
- index selection or authoritative predicate rechecks;
- encryption algorithms or leakage contract;
- the Dart public API;
- native library identity `rust_lib_dxtr_box`;
- the exact three-profile policy;
- the no-Tokio and no-GPUI-dependency decisions.

## PR4 boundary

PR4 remains responsible for cross-frontend compatibility evidence, benchmark evidence, documentation synchronization, and final 0.8 milestone closure. PR3 should not expand into a storage-format or query-engine redesign.
