# Dxtr_Box 0.8 Release Audit

## Scope

0.8 establishes Dxtr_Box as one Rust storage engine with two first-class frontends:

```text
Dart API -> FRB adapter -> shared Rust core -> redb
Rust API -------------> shared Rust core -> redb
```

There is no Rust-only storage format. Both frontends retain the durable `dxtr_box/1` contract and the existing `{box}.dxtr` files.

## PR map

- PR1 — architecture audit and shared-core/Rust-native foundation.
- PR2 — Rust-native CRUD/query/index surface and structured errors.
- PR3 — minimal/encryption/full profile validation, concurrency evidence, native consumer example.
- PR4 — cross-frontend storage compatibility, multi-frontend benchmark evidence, documentation/version closure.

## Cross-frontend compatibility evidence

`rust/tests/cross_frontend_compat.rs` is an external-consumer-style integration test and is included by `cargo test --all-targets` in the existing profile matrix.

It proves both directions against one physical database root and one `.dxtr` file per case:

```text
Rust-native DxtrBox/BoxHandle put
  -> close
  -> FRB adapter open/get

FRB adapter open/put
  -> close
  -> Rust-native DxtrBox/BoxHandle open/get
```

The fixtures are valid MessagePack payloads. No translation, export/import, alternate codec, or format conversion occurs between frontends.

Because this test contains only CRUD operations, it is intentionally valid under all three native profiles: `minimal`, `encryption`, and `full`. Query/index parity remains covered by the canonical shared-core tests plus the full-profile native integration suite.

## Multi-frontend benchmark evidence

Run:

```bash
bash tool/multi_frontend_benchmark.sh
```

The runner builds the release native library and writes two JSONL evidence files:

```text
build/multi-frontend/rust-native.jsonl
build/multi-frontend/dart-frb.jsonl
```

Both harnesses use the same logical workload shape:

- 1,000 MessagePack map records by default;
- point `get` hit;
- one-snapshot `getAll` of 100 keys;
- persisted equality index on `group`;
- equality query + descending `score` sort + `limit(50)`.

Each frontend reports per-operation sample totals and median nanoseconds/op. Iteration/sample/record counts are environment-configurable.

### Interpretation rule

The benchmark is diagnostic evidence, not a marketing leaderboard.

The Rust-native numbers include the public Rust facade, canonical shared core, codec validation/storage work, and redb. The Dart/FRB numbers additionally include Dart async/public API work, codec encode/decode where applicable, generated FRB transport, and cross-runtime boundary cost. Differences therefore help locate frontend/bridge overhead; they must not be described as a pure storage-engine speedup.

Do not compare numbers collected on different machines, build modes, record counts, or workload definitions as if they were an apples-to-apples ratio.

## 0.8 acceptance checklist

- [x] Rust frontend links directly to the shared Rust core; it does not wrap Dart/FRB.
- [x] Dart and Rust retain one canonical storage engine and `dxtr_box/1` format.
- [x] Rust-native CRUD, batch, query, sort/pagination, index, migration, encryption/profile coverage exists.
- [x] Structured `DxtrBoxError` is exposed to Rust consumers.
- [x] No Tokio commitment and no GPUI dependency were added.
- [x] Exactly three native profiles remain: minimal, encryption, full.
- [x] Rust-native external consumer example exists.
- [x] Cross-frontend write/read compatibility is tested in both directions.
- [x] Reproducible Rust-native versus Dart/FRB benchmark harness exists for get, batch read, and query.
- [x] Package version advances to `0.8.0-dev.1`.
- [ ] PR4 merge gate is green and PR4 is merged to `main`.

The milestone is considered closed only after the final unchecked item is satisfied. This avoids documenting 0.8 as complete before the repository merge gate proves the closure commit.

## Deferred

0.8 deliberately does not add GPUI integration, an ORM/schema generator, networking/sync, a fourth native profile, storage-format redesign, or a new query/encryption engine.
