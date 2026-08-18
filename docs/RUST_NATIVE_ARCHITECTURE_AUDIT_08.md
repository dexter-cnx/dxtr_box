# 0.8 Rust-native API / Multi-frontend Architecture Audit

Status: **PR1 architecture audit / foundation**

This document is the required Phase 1 audit before changing the Rust crate topology for 0.8.

The target architecture remains:

```text
Dart frontend
    |
    v
FRB adapter
    |
    v
shared Rust core
    |
    v
redb

Rust frontend
    |
    v
shared Rust core
    |
    v
redb
```

Required dependency direction:

```text
Dart API ----> FRB adapter ----┐
                              ├----> shared Rust core ----> redb
Rust API ---------------------┘
```

The audit intentionally prefers the smallest topology that creates real dependency separation. It does not propose an additional crate unless the current single-crate layout proves insufficient.

## Executive conclusion

The current repository already contains a mostly reusable Rust storage engine, but the crate boundary is not yet suitable as a first-class Rust frontend.

The main problem is not `redb`, query execution, indexing, encryption, or durable format. The main problem is **orchestration placement**:

- `db.rs`, `query.rs`, `index.rs`, `index_token.rs`, `crypto.rs`, and `codec.rs` contain the authoritative engine behavior or reusable engine helpers;
- `api.rs` currently mixes FRB-facing DTOs and stream types with shared orchestration such as mutation serialization, query execution, index lifecycle, and calls into the storage layer;
- most engine functions return `Result<_, String>`, because the current public native surface was designed primarily for FRB transport rather than native Rust error handling;
- the package already builds an `rlib`, and existing integration tests import the crate as an external Rust dependency without performing FRB runtime initialization;
- therefore 0.8 should **keep one Rust crate for now**, introduce an internal/shared core boundary inside that crate, then put both the FRB adapter and the Rust-native frontend on top of that boundary.

No storage-format change, query-engine rewrite, encryption redesign, fourth feature profile, Tokio runtime, or GPUI dependency is required.

## 1. Where authoritative storage behavior currently lives

### `rust/src/db.rs`

This is the primary authoritative storage layer.

It owns or directly coordinates:

- the `redb::Database` handles;
- the global base path;
- the open database registry and handle counts;
- box-name validation and `.dxtr` file resolution;
- durable `meta[format_version] = dxtr_box/1` handling;
- plaintext/encrypted open semantics;
- encryption-state reconstruction and key validation;
- authoritative record encode/decode on primary `data` rows;
- CRUD and batch CRUD;
- key listing and length;
- box deletion and close lifecycle;
- compaction and plaintext-to-encrypted migration;
- full-profile index-maintenance hooks inside the same redb write transactions as primary mutations;
- query helpers that read authoritative primary records.

`db.rs` should remain below both frontends. It is engine code, not an FRB adapter.

### `rust/src/query.rs`

This contains the canonical query semantics used by the native planner/executor:

- `QuerySpec`;
- `Filter`;
- `Comparison`;
- `LogicalOp`;
- `CompareOp`;
- `SortSpec`;
- `SortDirection`;
- `NullOrder`;
- field lookup;
- comparison evaluation;
- sort extraction, validation, and ordering;
- decoding of the current Dart-produced query payload.

The predicate/sort domain types are already normal Rust types and are good candidates for the shared-core query representation. The decoding function is transport-oriented and should not be the only construction path in 0.8.

### `rust/src/index.rs` and `rust/src/index_token.rs`

These contain persisted-index behavior and selection rules, including the encrypted equality-token path under `full`.

They are engine/planner code and should remain shared by both frontends.

### `rust/src/crypto.rs`

This contains encryption primitives and key derivation used by storage. It is not inherently FRB-specific.

### `rust/src/codec.rs`

This validates the MessagePack payload contract currently stored in primary records. The durable payload format remains shared by both frontends.

### `rust/src/api.rs`

This is currently both adapter and orchestration layer.

It calls the authoritative storage/query/index modules, but also owns behavior that should be reusable by a Rust frontend, including:

- per-box mutation locking;
- lifecycle orchestration;
- query execution across planner/index candidates + authoritative recheck + sorting/pagination;
- index lifecycle orchestration.

That shared behavior should move behind a frontend-neutral core boundary.

## 2. FRB-specific modules and types

### Fully FRB-specific

`rust/src/frb_generated.rs`

- generated transport glue;
- must remain adapter-only;
- must never be required by the Rust-native frontend.

### FRB-coupled portions of `api.rs`

`api.rs` directly imports:

```rust
use flutter_rust_bridge::frb;
use crate::frb_generated::StreamSink;
```

FRB-specific concerns include:

- `#[frb(sync)]` and `#[frb(stream_dart_await)]` annotations;
- `StreamSink<NativeBoxEvent>`;
- the global watcher registry keyed by Dart watcher identifiers;
- adapter DTOs shaped for generated bindings:
  - `NativeBoxEvent`;
  - `NativeBoxEventType`;
  - `NativeQueryRecord`;
  - `NativeBatchRecord`;
  - `NativeIndexDefinition`.

Not every `Native*` type is semantically bridge-only, but their current placement and shape are dictated by the Dart/FRB boundary. They should not become the Rust API merely because they already exist.

## 3. Reusability of query/index/encryption domain types

### Query

Reusable with small changes.

The core query types are already Rust-native structs/enums. The main limitation is that `QuerySpec` currently enters the engine through `decode_query(&[u8])`, which decodes the Dart transport payload.

0.8 should make `QuerySpec` itself the canonical engine input and keep payload decoding in the FRB adapter path:

```text
Dart BoxQuery
  -> MessagePack transport decode
  -> QuerySpec
  -> shared planner/executor

Rust query builder
  -> QuerySpec
  -> shared planner/executor
```

This avoids a second query AST and avoids making Rust callers serialize a fake Dart payload simply to execute a query.

### Indexes

Reusable.

Index creation, listing, deletion, candidate narrowing, persisted definitions, plaintext scalar representation, encrypted equality tokens, and authoritative rechecks already operate in Rust engine code.

The Rust frontend should expose ergonomic definitions over the same engine calls; it must not create a separate index subsystem.

### Encryption

Reusable.

The durable encryption format and authenticated record behavior belong to the storage core. Rust-native open/create/migration should call the same logic and preserve the exact same key validation and AEAD behavior.

No new Rust-only encryption format or shortcut is acceptable.

## 4. Bridge DTOs that should become native Rust domain types

The current bridge DTOs reveal several domain concepts that should exist independently of FRB.

### Records

Current adapter shapes:

```text
NativeQueryRecord { key, value }
NativeBatchRecord { key, value }
```

These are the same domain concept. 0.8 should define one frontend-neutral record type, for example:

```rust
pub struct BoxRecord {
    pub key: String,
    pub value: Vec<u8>,
}
```

The FRB adapter may map it to generated-friendly DTOs if required, while the Rust API can return it directly or expose more idiomatic iterator/collection forms.

Do not keep two engine record types merely because FRB previously had two DTO names.

### Index definitions

Current adapter shape:

```text
NativeIndexDefinition { name, field }
```

This is a real domain concept and should move to the shared core as a normal Rust type.

### Events

The semantic event is domain-level:

```text
put | delete | clear
box name
optional key/value
```

But `StreamSink` registration and watcher IDs are FRB transport concerns.

A shared core may eventually expose an event value type or internal publisher hook, while the FRB adapter remains responsible for `StreamSink` subscription lifecycle. 0.8 PR1 should not invent a general async event framework solely for Rust parity.

## 5. Serialization that exists only because Dart calls the engine

The most important transport-only serialization is the query payload decoded by `query::decode_query`.

Current path:

```text
Dart BoxQuery AST
  -> MessagePack query payload
  -> FRB Vec<u8>
  -> query::decode_query
  -> QuerySpec
```

For Rust-native use, serializing `QuerySpec` to the Dart wire representation and immediately decoding it would be unnecessary coupling.

The shared executor should accept `&QuerySpec` or owned `QuerySpec` directly. The FRB adapter keeps `decode_query` as its boundary conversion.

Primary record payload serialization is different: MessagePack dynamic values are part of the current shared storage contract, not merely FRB transport. A Rust frontend may initially expose raw encoded values and later provide safe codec helpers, but it must remain compatible with the same persisted bytes.

The `@dxtr:*` wire tags and `dxtr_box/1` durable identity remain unchanged.

## 6. Errors currently flattened to strings for FRB

The storage/query/index layers predominantly use:

```rust
Result<T, String>
```

This is convenient for FRB but insufficient for a first-class Rust API.

Examples of currently string-flattened categories include:

- engine not initialized;
- invalid box name;
- box missing/not open;
- redb open/read/write/commit failures;
- unsupported feature/profile operation;
- invalid or missing encryption key;
- encrypted authentication failure;
- compaction/migration busy state;
- malformed query payload;
- invalid query shape/operator/value;
- unsupported or incompatible sort values;
- index lifecycle/planner failures.

0.8 should introduce a structured public error such as `DxtrBoxError` at the shared-core/native boundary.

The FRB adapter may convert that structured error to the existing string contract initially to preserve Dart compatibility.

Do not force every deep helper to be rewritten in one PR. A staged conversion is acceptable:

```text
legacy internal String errors
  -> shared boundary maps/classifies
  -> DxtrBoxError for Rust frontend
  -> FRB adapter maps to stable String for Dart
```

Then deeper modules can migrate to typed errors incrementally when the classification is clear and non-disruptive.

## 7. Does the current crate link cleanly as an `rlib`?

Yes, by declared crate topology and by existing tests.

`rust/Cargo.toml` already declares:

```toml
crate-type = ["cdylib", "staticlib", "rlib"]
```

Existing files under `rust/tests/` are external integration tests and import the crate by package name, for example:

```rust
use rust_lib_dxtr_box::{
    clear, close_box, create_index, drop_index, init_db, list_indexes,
    open_box, put, scan_query,
};
```

Those tests demonstrate that the crate is usable as an `rlib` from normal Rust integration-test code.

However, the exported API is still the FRB-shaped top-level `api::*` surface. Linking as an `rlib` is therefore already possible, while **having a stable, idiomatic Rust-native frontend is not**.

No second crate is required merely to obtain `rlib` output.

## 8. Flutter/FRB-specific dependencies and features

### Direct dependency

`flutter_rust_bridge = 2.8.0` is currently unconditional in `Cargo.toml`.

Current source coupling is concentrated in:

- `api.rs` annotations and `StreamSink` import;
- `frb_generated.rs`.

The engine modules themselves do not need FRB concepts for storage semantics.

### Native feature profiles

The exact supported profiles remain:

```text
minimal
  core CRUD/lifecycle/watch-compatible native surface

encryption
  minimal + encryption

full
  encryption + maintenance + query/index support
```

0.8 must not add a fourth native profile.

The Rust-native frontend should respect the same compile-time capability matrix. Query/index methods under non-`full` builds should be unavailable or return a clearly structured unsupported-capability error according to the final API design; do not silently provide a different implementation.

### Dependency decision for PR1

Do not make FRB optional solely for aesthetics in the first refactor. The Flutter plugin still requires generated bindings and current CI validates those bindings.

First establish module dependency direction. After both frontends depend on shared core rather than one another, making the bridge dependency optional can be evaluated separately if there is a real consumer/build-size benefit and it does not violate the three-profile rule.

## 9. Minimum module/crate boundary changes required

Recommended smallest topology:

```text
rust/src/
  lib.rs
  core/                 shared frontend-neutral orchestration
    mod.rs
    error.rs
    types.rs
    query_executor.rs   only if extraction is clearer than one module
  api.rs                FRB adapter only
  db.rs                 authoritative redb storage
  query.rs              canonical query domain + semantics
  index.rs              persisted index engine
  index_token.rs
  crypto.rs
  codec.rs
  frb_generated.rs      generated bridge glue
  native.rs             first-class Rust frontend, introduced in PR2
```

The exact filenames may be smaller; the dependency rule matters more than folder count.

### PR1 extraction target

Move only logic that is genuinely shared:

1. per-box mutation serialization/locking;
2. lifecycle orchestration over `db`;
3. query execution after a canonical `QuerySpec` exists;
4. index lifecycle orchestration;
5. shared record/index domain types;
6. shared error boundary.

Keep in `api.rs`:

1. FRB attributes;
2. Dart parameter/return DTO conversion;
3. `StreamSink` watcher registration and delivery;
4. query payload decoding from Dart transport bytes before calling shared execution;
5. compatibility conversion of structured errors to the existing Dart string error surface where needed.

### No new crate in PR1

A separate `dxtr_box_core` crate would add release/versioning/build complexity without solving a demonstrated problem that modules cannot solve.

Revisit crate split only if one of these becomes true:

- the Rust frontend must consume the engine without linking any bridge code and feature-gating cannot provide that cleanly;
- independent versioning/publishing of the engine becomes a real requirement;
- cyclic dependency pressure appears inside the single crate;
- native consumers require a substantially different build topology that modules cannot represent safely.

Until then, one crate is the lower-risk architecture.

## 10. Do current Rust tests exercise the engine without FRB initialization?

Yes.

The existing files in `rust/tests/` are native Rust integration tests. They call the currently exported Rust functions directly and do not initialize a Flutter engine or an FRB runtime.

Examples cover:

- query execution;
- persisted index lifecycle;
- encrypted-range planner behavior;
- crash/reopen behavior;
- reduced-profile index guards.

This is valuable evidence that the storage engine itself does not require a Dart runtime to execute.

The limitation is that these tests still call the FRB-shaped top-level API functions. 0.8 validation should add **external-consumer-style tests against the new Rust-native frontend**, not merely keep using the compatibility exports.

## Dependency audit summary

Current effective dependency shape:

```text
lib.rs
  -> api.rs -------------------------------------------┐
       -> FRB annotations / StreamSink                 |
       -> watcher registry                             |
       -> mutation locks                               |
       -> query orchestration                          |
       -> index orchestration                          |
       -> db/query/index ------------------------------+--> redb / engine
  -> frb_generated.rs ---------------------------------┘
  -> db.rs
  -> query.rs
  -> index.rs
  -> crypto.rs
  -> codec.rs
```

Target after PR1/PR2:

```text
lib.rs
  -> api.rs (FRB adapter) ----------┐
                                    |
  -> native.rs (Rust frontend) -----+--> core --> db/query/index/crypto/codec --> redb
                                    |
  -> frb_generated.rs <-------------┘ adapter-only transport glue
```

No frontend may call through the other frontend.

## API direction for the Rust frontend

0.8 should use Rust conventions rather than mechanically mirroring Dart.

Directional example:

```rust
let db = DxtrBox::open(path)?;
let assets = db.box_("assets")?;

let rows = assets
    .query()
    .where_("workplace_id")
    .equals(workplace_id)
    .order_by("captured_at", SortOrder::Descending)
    .limit(200)
    .find()?;
```

This example is not a requirement to introduce an ORM, schema system, generated model layer, or async runtime.

Minimum conventions:

- `Result<T, DxtrBoxError>`;
- `Path` / `PathBuf` for filesystem entry points;
- explicit ownership/lifetimes;
- documented `Send` / `Sync` behavior;
- no forced Tokio commitment;
- no GPUI dependency;
- canonical queries flow into the same `QuerySpec`/planner semantics used by Dart.

## Concurrency and process model observations

The current engine uses process-global registries for:

- base path;
- open databases/handle counts;
- compaction/migration state;
- per-box mutation locks in `api.rs`;
- FRB watchers in `api.rs`.

This means a first Rust-native facade should not pretend that independent `DxtrBox` instances are isolated database engines if they still share these registries internally.

PR2 must document the real semantics explicitly.

Do not redesign the process model in 0.8 unless the native frontend exposes a correctness problem that cannot be solved while preserving current durable behavior.

## Validation strategy resulting from this audit

### PR1

- existing Rust tests must remain green under all three profiles;
- generated FRB bindings must remain reproducible;
- `rlib` must remain part of `crate-type`;
- no storage-format or feature-profile change;
- add a compile/runtime foundation test only when a shared-core/native symbol is introduced.

### PR2

External-consumer-style Rust-native tests should cover at minimum:

```text
open
put/get/delete
batch reads
reopen
query
index
sorting
pagination
structured errors
```

### PR3

Add profile/concurrency coverage and examples, including encryption and migration where the feature profile supports them.

### PR4

Add cross-frontend compatibility evidence:

```text
Rust API write -> Dart/FRB-compatible read
Dart/FRB-compatible write -> Rust API read
```

Both directions must use the same `dxtr_box/1` database file and the same canonical payload/query semantics.

## Accepted PR decomposition after audit

The four-PR strategy from the project handoff remains appropriate with one clarification: PR1 should create module-level separation inside the current crate, not split crates.

```text
PR1 — architecture audit + shared-core/FRB module boundary foundation
PR2 — Rust-native CRUD/query API + structured public errors
PR3 — profiles/concurrency + native integration tests/examples
PR4 — cross-frontend validation + benchmark evidence + docs/milestone closure
```

If PR1 extraction becomes too large for safe review, split the code extraction from this audit into an additional small PR, but do not merge a speculative second crate merely to preserve a nominal four-PR count.

## 0.8 invariants

0.8 must preserve:

- `dxtr_box/1` readable and writable compatibility;
- one authoritative primary `data` table;
- transactional index maintenance with primary mutations;
- authoritative primary-record predicate rechecks;
- full AEAD authentication for encrypted reads;
- encrypted equality-index behavior and encrypted range scan fallback;
- deterministic sort-before-pagination semantics;
- current point-read and one-snapshot batch-read performance architecture;
- exact `minimal | encryption | full` profile set;
- Dart >= 3.4 / Flutter >= 3.22;
- flutter_rust_bridge 2.8.0 until deliberately reprioritized;
- redb 2.1.0;
- native library/package identities;
- existing Flutter/Dart public API compatibility unless a separate explicit change is justified.

## Explicit non-goals confirmed by the audit

Do not turn this work into:

- GPUI integration;
- GUI framework support code;
- ORM/schema/model generation;
- sync/CRDT/vector-clock infrastructure;
- networking or server functionality;
- storage-format redesign;
- a second query engine;
- a new encryption format;
- a fourth feature profile;
- Tokio/async-runtime commitment;
- a broad Dart API redesign.

## PR1 implementation decision

Proceed with **module extraction inside the existing crate**.

The first code move should make this statement true:

> FRB-specific code depends on shared core; shared core does not import `flutter_rust_bridge`, `frb_generated`, or `StreamSink`.

Only after that boundary exists should PR2 expose the stable Rust-native facade.
