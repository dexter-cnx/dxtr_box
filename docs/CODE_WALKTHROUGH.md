# dxtr_box Code Walkthrough

This walkthrough describes the self-contained Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, completed read-path hardening, and the active 0.6 Query / Index + Encryption Hardening milestone.

Dxtr_Box is positioned as its own native local database for Flutter. Hive/Hive CE is retained only as migration/interoperability tooling and a benchmark/reference peer.

## 1. Package boundary

`dxtr_box` is one self-contained Flutter FFI plugin:

```text
dxtr_box/
  lib/                 Dart API + generated FRB bindings
  rust/                Rust crate/library: rust_lib_dxtr_box
  cargokit/            native build integration
  android/
  ios/
  macos/
  linux/
  windows/
  example/
```

Stable compatibility:

```text
Dart >= 3.4
Flutter >= 3.22
flutter_rust_bridge = 2.8.0
redb = 2.1.0
native profiles = minimal | encryption | full
```

Dart 3.13 recorded-use/native tree shaking remains deferred.

## 2. Runtime boundary

```text
Flutter app
  -> DxtrBox / Box / query + migration types
  -> native capability seams
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lightweight metadata, lifecycle guards, query objects, and optional Hive CE migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance, and plaintext-to-encrypted migration.

## 3. Storage identity

Each box maps to `{base_path}/{box_name}.dxtr`.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

Core tables are `data` and `meta`; `full` additionally maintains persisted index definitions and entries.

## 4. Mutation atomicity

```text
Box.put / putAll / delete / deleteAll / clear
  -> DxtrCodec
  -> FRB
  -> Rust validation
  -> optional encryption
  -> one redb write transaction
  -> primary + index changes
  -> one commit
  -> watch event after commit only
```

Primary data is authoritative. Persisted indexes are derived state.

## 5. Production point-read path

Public Dart API remains asynchronous:

```text
Box.get
  -> NativeDxtrApi.get : Future<Uint8List?>
  -> FrbNativeDxtrApi.get
  -> generated FRB sync call
  -> Rust api::get #[frb(sync)]
  -> db::get
  -> redb read transaction + DATA lookup
  -> optional ChaCha20Poly1305 decrypt/authenticate
  -> validate_message_pack
  -> Vec<u8> through FRB
  -> DxtrCodec.decode
```

`Box.containsKey` follows the same authoritative native path and Rust `contains_key` also uses `#[frb(sync)]`.

Only these tiny single-key read entrypoints use synchronous FRB dispatch. Query, batch reads, scans, mutations, and migrations remain asynchronous.

0.5 controlled evidence:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

No Dart whole-box cache, metadata-backed authoritative shortcut, or long-lived stale read snapshot was introduced.

## 6. Production batch-read path

Public API:

```dart
Future<List<MapEntry<String, dynamic>>> getAll(Iterable<String> keys)
```

Execution:

```text
Box.getAll
  -> validate all requested keys
  -> NativeBatchReadApi.getAll
  -> FrbNativeDxtrApi.getAll
  -> generated asynchronous FRB getAll
  -> Rust api::get_all
  -> db::get_all
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative key lookups
  -> decrypt/authenticate every encrypted hit
  -> validate MessagePack every hit
  -> one response
  -> Dart DxtrCodec.decode per hit
```

Hits preserve input order, misses are omitted, duplicate requested keys remain duplicate result entries, and empty input avoids a native crossing.

The batch entrypoint intentionally stays asynchronous so large batches do not synchronously occupy the Dart/UI isolate.

## 7. Query execution

`Box.query(BoxQuery)` is one structured asynchronous FRB call:

```text
Box.query
  -> serialize query AST
  -> one FRB call
  -> one redb ReadTransaction snapshot
  -> optional persisted-index candidate narrowing
  -> authoritative primary reads
  -> optional decrypt/authenticate
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

The planner may narrow work through derived indexes, but a candidate is never trusted as the final answer. Primary records are authoritative and predicates are re-evaluated.

## 8. Plaintext persisted-index path

`rust/src/index.rs` owns persisted index definitions and entry maintenance.

```text
createIndex
  -> validate name/field
  -> one redb write transaction
  -> scan primary DATA for backfill
  -> derive scalar entries
  -> persist definition + entries
  -> commit
```

Normal mutations update primary data and derived index entries in the same write transaction.

Current index behavior:

- exact dotted-field matching;
- equality and ordered/range candidate narrowing;
- deterministic index selection;
- AND intersection across usable indexes;
- record-key candidates only;
- full authoritative predicate recheck;
- no index-backed ORDER BY yet.

## 9. Encrypted query/index boundary entering 0.6

Encrypted primary records remain authenticated ciphertext. Native scan queries work because Rust decrypts/authenticates each authoritative record before evaluating the predicate.

Persisted index creation is intentionally blocked for encrypted boxes in `rust/src/index.rs`:

```text
persisted indexes are not yet supported for encrypted boxes; native scan queries remain available
```

That guard exists because the plaintext index representation stores scalar-derived bytes suitable for equality/range matching. Reusing it unchanged for encrypted boxes would leak indexed values/order outside the authenticated ciphertext.

0.6 starts from this rule:

> Do not remove the encrypted-index guard until the persisted representation and leakage contract are accepted explicitly.

The native integration regression guard verifies both sides:

```text
encrypted createIndex -> rejected
encrypted query scan  -> still works
listIndexes            -> remains empty
```

This makes a future encrypted-index change deliberate and review-visible rather than an accidental weakening.

## 10. Preferred encrypted equality-index shape

If 0.6 accepts encrypted equality indexing, the preferred direction is keyed deterministic equality tokens rather than plaintext scalar bytes.

Conceptually:

```text
plaintext scalar
  -> canonical query/index scalar encoding
  -> keyed/domain-separated token(box key, index identity, scalar)
  -> persisted token + derived record-key candidate
```

A query equality operand derives the same token, locates candidates, then performs the normal authoritative primary decrypt/authenticate + full predicate recheck.

Security notes:

- equality/frequency classes can still leak when deterministic tokens repeat;
- raw scalar plaintext must not appear in the index;
- index/field context must be domain-separated;
- tokens cannot be treated as order-preserving;
- equality-token design does not justify encrypted range indexing.

The exact construction is not approved merely by this walkthrough; `docs/QUERY_INDEX_ENCRYPTION_06.md` is the normative 0.6 decision record.

## 11. Encrypted range-index decision

Range indexing for encrypted fields is optional in 0.6.

A design that preserves ordering necessarily exposes more information than equality-only tokens. If the leakage/complexity tradeoff is not compelling, encrypted `>`, `>=`, `<`, `<=`, and `between` remain scan-backed while plaintext boxes retain persisted range indexes.

An evidence-backed rejection is an acceptable milestone result.

## 12. Encryption/profile safety

Profiles remain exactly:

```text
minimal
encryption
full
```

`full` contains query/index implementation and encryption capability. Do not add an `encrypted-index` profile.

Every encrypted result path retains ChaCha20Poly1305 authentication. A persisted index, if added, is derived acceleration state only and never an authorization/authenticity substitute.

## 13. Optional Hive CE migration path

Core `dxtr_box` has no runtime Hive CE dependency.

```text
migrateFromHiveCe
  -> validate/enumerate source
  -> key/value conversion
  -> collision detection
  -> DxtrCodec preflight
  -> acquire exclusive destination reservation
  -> create destination
  -> migration-only internal open
  -> one Box.putAll
  -> close
  -> release reservation
```

This remains interoperability tooling, not the product architecture target. Ordinary opens are excluded while migration owns the destination. Failure cleanup removes migration-owned state and releases its reservation.

## 14. Read-session decision retained from 0.5

Ordinary read operations continue to create fresh authoritative redb snapshots per call. A reusable long-lived read transaction was rejected because it would expose intentionally stale snapshot semantics while avoiding only a small measured transaction/table-open cost.

Known multi-key workloads use `getAll` instead.

## 15. Benchmarks

Existing evidence remains diagnostic, not a speed gate.

0.6 extends query/index evidence where useful:

```text
plaintext scan vs indexed equality
plaintext scan vs indexed range
encrypted scan vs encrypted equality index (if implemented)
index create/backfill cost
mutation overhead with indexes
reopen/query
```

Representative 100 / 1,000 / 10,000 record datasets should be used where CI cost is reasonable.

Hive CE, Sembast, and SQLite remain comparison peers; none defines the product architecture or success criteria.

## 16. FRB drift and package gates

Checked-in bindings are generated with FRB 2.8.0. Full CI regenerates them and fails on diff.

Package readiness remains:

```text
make package-readiness
  -> dart doc
  -> dart pub publish --dry-run --ignore-warnings
```

## 17. Native-size policy

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
```

Minimal, encryption, and full are measured independently.

## 18. Staged published consumers

`tool/validate_published_consumer.dart` validates the consumer-visible package payload on Android, iOS, macOS, Linux, and Windows.

## 19. Change-aware CI

```text
change-detection
      |
      v
   Fast CI
      |
      +--> affected expensive validation during Draft iteration
      |
      v
Merge Gate / full quality bar
```

`make preflight` mirrors Fast CI:

```text
format-check
analyze
test-fast
contract-check
rust-check
```

Full validation remains mandatory before merge.

## 20. 0.6 implementation sequence

```text
PR 1 — threat model + safe-default regression guard + product/milestone docs
PR 2 — encrypted equality index, only if representation is accepted
PR 3 — plaintext planner/range/index polish + measured evidence
PR 4 — encrypted range/index decision
PR 5 — compatibility cleanup + closure audit
```

0.6 deliberately does not grow into ORM, sync, or schema-framework work.

## 21. Invariants to preserve

- Dart >=3.4 / Flutter >=3.22.
- FRB exactly 2.8.0.
- Native identity `rust_lib_dxtr_box`.
- Exactly three native profiles.
- `dxtr_box/1` remains readable.
- Primary data authoritative over indexes.
- `get`, `containsKey`, and `getAll` remain authoritative native reads.
- No Dart whole-box cache.
- No implicit long-lived stale snapshot.
- Full encrypted authentication.
- No plaintext scalar leakage from encrypted indexes by accident.
- Query/index/migration correctness.
- Native-size regression policy.
- Five-platform staged consumer builds.
- Change-aware CI never weakens the final merge quality bar.
- Product docs describe Dxtr_Box as its own native local database, not as a Hive replacement.
- Dart 3.13 recorded-use/native tree shaking remains deferred.

Important targets:

```text
make preflight
make package-readiness
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make benchmark-comparison-correctness
make benchmark-comparison
make benchmark-query-index
make benchmark-read-path
make benchmark-batch-read
make native-size-regression
make published-consumer-android
make published-consumer-ios
make published-consumer-macos
make published-consumer-linux
make published-consumer-windows
```

See `docs/QUERY_INDEX_ENCRYPTION_06.md` for the normative 0.6 design/decision record and `docs/PROJECT_HANDOFF.md` for current execution state.
