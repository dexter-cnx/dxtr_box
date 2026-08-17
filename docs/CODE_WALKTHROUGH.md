# dxtr_box Code Walkthrough

This walkthrough describes the publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution path, completed 0.4 hardening, completed 0.5 read-path work, and the current 0.6 Query / Index + Encryption Hardening milestone.

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

Dart owns public ergonomics, MessagePack encoding/decoding, lightweight metadata, lifecycle guards, query objects, and optional migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance, and plaintext-to-encrypted migration.

## 3. Product identity

Dxtr_Box is a native local database for Flutter. It is not defined as a Hive/Hive CE replacement.

Core differentiators:

- Rust/redb ACID storage;
- simple box-style asynchronous Flutter API;
- optimized authoritative reads;
- declarative native queries;
- persisted secondary indexes;
- first-class authenticated encryption;
- encrypted equality-index narrowing under `full`;
- native watch fan-out;
- crash/reopen durability validation;
- Android/iOS/macOS/Linux/Windows package consumers.

Hive CE remains useful as an optional migration source and benchmark/reference peer only.

## 4. Storage identity

Each box maps to `{base_path}/{box_name}.dxtr`.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

Core tables are `data` and `meta`; `full` additionally maintains persisted index definitions and entries.

## 5. Mutation atomicity

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

For encrypted boxes, index maintenance decrypts/authenticates the prior stored record when required, derives equality tokens from plaintext query scalar semantics, mutates derived entries, and commits those changes atomically with the new primary ciphertext.

## 6. Production point-read path after 0.5

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

## 7. Production batch-read path

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
  -> one Vec<NativeBatchRecord> response
  -> Dart DxtrCodec.decode per hit
```

Semantics:

```text
input order for hits: preserved
missing keys:         omitted
duplicate input keys: duplicate result entries
empty input:          empty result without native crossing
```

The batch entrypoint intentionally stays asynchronous. A large key set must not inherit the single-key `#[frb(sync)]` policy and synchronously occupy the Dart/UI isolate.

0.5 hosted evidence reached ~8.59x improvement for 1,000 keys versus N independent public `get` calls.

## 8. Read-session boundary

0.5 investigated carrying a redb `ReadTransaction` across multiple Dart calls and deliberately did not add that API.

```text
ordinary read call
  -> fresh redb ReadTransaction
  -> authoritative snapshot for that call
  -> transaction ends with the call
```

A reusable transaction would be a fixed snapshot and therefore stale relative to commits made after session creation. Because `getAll` already handles known multi-key work in one call, ordinary reads preserve fresh-per-call semantics.

Detailed decision: `docs/READ_SESSION_INVESTIGATION_05.md`.

## 9. Query execution

`Box.query(BoxQuery)` remains one structured query through one asynchronous FRB call:

```text
Box.query
  -> serialize query AST
  -> one FRB call
  -> one redb ReadTransaction snapshot
  -> optional index candidate narrowing
  -> authoritative primary reads
  -> optional decrypt/authenticate
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

Persisted indexes narrow candidates only; they do not replace predicate re-evaluation and do not satisfy ORDER BY.

## 10. Plaintext index path

Plaintext indexes retain the existing persisted scalar representation and support equality plus ordered/range candidate narrowing.

```text
query filter
  -> query::index_candidates
  -> deterministic matching index selection
  -> persisted scalar/range lookup
  -> candidate record-key set
  -> authoritative primary read
  -> full predicate recheck
```

AND groups can intersect multiple candidate sets. Raw MessagePack bytes are not treated as semantic numeric ordering; scalar encoding remains explicit.

## 11. 0.6 encrypted equality-index path

PR2 accepts encrypted persisted indexes for equality narrowing only.

Creation/backfill:

```text
Box.createIndex
  -> FRB
  -> index::create
  -> read encrypted primary record
  -> ChaCha20Poly1305 authenticate/decrypt using record-key AAD
  -> extract canonical query scalar
  -> BLAKE2b keyed MAC token
       key: authenticated box key material
       domain: index name + field
  -> persist token + record-key derived entry
  -> commit definition + derived entries
```

Query:

```text
encrypted Box.query(equal)
  -> query::index_candidates
  -> retain encrypted equality candidates only
  -> select matching persisted index
  -> canonicalize query scalar
  -> derive same domain-separated BLAKE2b keyed token
  -> exact token lookup
  -> candidate record keys
  -> authoritative encrypted primary read
  -> ChaCha20Poly1305 authenticate/decrypt
  -> full predicate re-evaluation
  -> sort / offset / limit
```

Mutation:

```text
put / putAll / delete / deleteAll
  -> one redb write transaction
  -> authenticate/decrypt old value when index removal needs it
  -> derive old/new equality tokens
  -> remove/add index entries
  -> write/remove authoritative primary record
  -> one commit
```

Security semantics:

- raw plaintext scalar values are not persisted in encrypted index entries;
- deterministic tokens intentionally reveal equality classes/frequency;
- index/field names and record identifiers remain visible as derived metadata;
- tokens are not order-preserving;
- every candidate is authenticated/decrypted and predicate-rechecked before return.

## 12. Encrypted range fallback

Encrypted `>`, `>=`, `<`, `<=`, and `between` predicates do not use equality tokens as fake ordering.

```text
encrypted ordered/range filter
  -> no usable encrypted index candidate
  -> primary key scan
  -> authenticate/decrypt each relevant record
  -> full predicate evaluation
  -> sort / offset / limit
```

PR3 decides whether any encrypted range representation is justified. Scan-only is an acceptable final decision.

## 13. 0.6 implementation sequence — four PRs

```text
PR 1 — threat model + safe-default regression guard + milestone/product docs
PR 2 — encrypted equality index + plaintext planner/range/index polish + benchmark evidence
PR 3 — encrypted range/index decision; implementation optional, evidence-backed rejection acceptable
PR 4 — core reliability/API closure + 0.6 audit
```

PR4 is explicitly not a Hive/Hive CE parity pass.

## 14. PR2 size/performance evidence

The first BLAKE3 implementation exceeded the native-size regression budget. PR2 replaced it with BLAKE2b keyed MAC while reusing the BLAKE2 implementation already present through Argon2.

Measured Linux x64 full-profile delta:

```text
2,385,720 -> 2,416,152 bytes
+30,432 bytes / +1.276%
PASS
```

Validated runtime head before docs sync:

```text
commit 5346c1176b2753cea9fc248b60055215041815c9
CI run 32069766813: success
```

The query/index timing harness remains diagnostic-only and now includes encrypted equality scan/index scenarios in addition to plaintext scenarios:

```bash
make benchmark-query-index
```

Do not turn hosted timing into a merge threshold.

## 15. Native profiles

Profiles remain exactly:

```text
minimal
encryption
full
```

Do not add a fourth profile for encrypted indexing or performance tuning.

The equality-token dependency is full-profile-only at the feature level; the design intentionally avoids adding a second heavy hash implementation.

## 16. Migration/interoperability

Core `dxtr_box` has no runtime Hive CE dependency. Hive CE migration is optional tooling:

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

This interoperability path does not define product parity or 1.0 success.

Plaintext-to-encrypted migration still rejects a source box with persisted plaintext indexes. The caller must drop those indexes before migration and recreate them after opening the encrypted box so encrypted derived state is generated under the accepted token contract.

## 17. FRB drift and package gates

Checked-in bindings are generated with FRB 2.8.0. Full CI regenerates them and fails on any diff.

Package readiness remains:

```text
make package-readiness
  -> dart doc
  -> dart pub publish --dry-run --ignore-warnings
```

## 18. Native-size policy

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
```

Minimal, encryption, and full are measured independently.

## 19. Staged published consumers

`tool/validate_published_consumer.dart` validates the consumer-visible package payload on Android, iOS, macOS, Linux, and Windows.

## 20. Change-aware CI

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
- No plaintext scalar bytes in encrypted index entries.
- Encrypted equality-token leakage remains documented.
- Encrypted range predicates remain scan-backed unless PR3 explicitly accepts a representation.
- Query/index/migration correctness.
- Native-size regression policy.
- Five-platform staged consumer builds.
- Change-aware CI never weakens the final merge quality bar.
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

See `docs/QUERY_INDEX_ENCRYPTION_06.md` for the normative 0.6 security/decision record and `docs/PROJECT_HANDOFF.md` for current execution state.
