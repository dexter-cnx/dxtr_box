# dxtr_box Code Walkthrough

This walkthrough covers the publishable Flutter FFI package boundary, Dart -> flutter_rust_bridge -> Rust/redb execution paths, completed 0.4/0.5 work, and the final 0.6 Query / Index + Encryption Hardening contract.

## 1. Package boundary

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
format_version = dxtr_box/1
```

## 2. Runtime ownership

```text
Flutter app
  -> DxtrBox / Box / query + migration types
  -> generated flutter_rust_bridge bindings
  -> Rust API
  -> redb
```

Dart owns public ergonomics, MessagePack encoding/decoding, lifecycle guards, query objects, and optional migration preflight.

Rust owns durable storage, transactions, encryption, native watchers, query evaluation, persisted indexes, maintenance, and plaintext-to-encrypted migration.

## 3. Product identity

Dxtr_Box is a native local database for Flutter, not a Hive/Hive CE replacement.

Hive CE remains optional migration/interoperability tooling and a benchmark/reference peer.

## 4. Storage and mutation atomicity

Each box maps to `{base_path}/{box_name}.dxtr`.

Durable identity:

```text
meta[format_version] = dxtr_box/1
```

Mutation path:

```text
Box.put / putAll / delete / deleteAll / clear
  -> DxtrCodec
  -> FRB
  -> Rust validation
  -> optional encryption
  -> one redb write transaction
  -> primary + derived index changes
  -> commit
  -> watch event after commit only
```

Primary data is authoritative. Persisted indexes are derived state.

## 5. Production point-read path after 0.5

Public Dart API remains asynchronous:

```text
Box.get
  -> NativeDxtrApi.get : Future<Uint8List?>
  -> FrbNativeDxtrApi.get
  -> generated FRB sync dispatch
  -> Rust api::get #[frb(sync)]
  -> db::get
  -> fresh redb read transaction
  -> optional ChaCha20Poly1305 authenticate/decrypt
  -> MessagePack validation
  -> Dart decode
```

`Box.containsKey` uses the same small generated sync-dispatch optimization internally.

Only tiny single-key reads use this FRB call mode. Queries, batch reads, mutations, scans, and migrations remain asynchronous.

0.5 controlled boundary evidence:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

No Dart whole-box cache or long-lived stale read snapshot was introduced.

## 6. Batch-read path

```text
Box.getAll
  -> validate requested keys
  -> one asynchronous FRB crossing
  -> Rust api::get_all / db::get_all
  -> one redb ReadTransaction
  -> one DATA table open
  -> N authoritative key lookups
  -> decrypt/authenticate each encrypted hit
  -> MessagePack validation
  -> one response
  -> Dart decode per hit
```

Semantics:

```text
hit order: preserved
missing keys: omitted
duplicate input keys: duplicate output entries
```

## 7. Query execution

```text
Box.query(BoxQuery)
  -> serialize query AST
  -> one asynchronous FRB call
  -> one redb ReadTransaction snapshot
  -> optional persisted-index candidate narrowing
  -> authoritative primary reads
  -> optional decrypt/authenticate
  -> full predicate re-evaluation
  -> deterministic semantic sort
  -> offset / limit
  -> one response
```

Persisted indexes narrow candidates only. They do not replace predicate re-evaluation and do not currently satisfy ORDER BY.

## 8. Plaintext index execution

Plaintext indexes persist sortable scalar representations and may narrow:

```text
equal
>
>=
<
<=
between
```

Planner behavior includes deterministic index selection and multi-index intersection for compatible AND predicates.

Even after index narrowing, primary records are re-read and the full predicate is evaluated.

## 9. Encrypted equality index after PR2

PR #40 introduced encrypted equality narrowing under the `full` profile.

```text
encrypted equality query
  -> query scalar canonicalization
  -> BLAKE2b keyed MAC token
     domain separated by index name + field
  -> exact token candidate lookup
  -> authoritative encrypted primary read
  -> ChaCha20Poly1305 authenticate/decrypt
  -> full predicate re-evaluation
  -> sort / offset / limit
```

The token is deterministic so repeated equal values intentionally reveal equality classes/frequency. Raw plaintext scalar values are not persisted.

Index create/backfill and mutation/delete maintenance stay in the same redb write transaction as primary data.

## 10. Encrypted range execution after PR3

PR #42 made the range policy explicit: encrypted ordered/range predicates remain scan-backed in 0.6.

Planner contract:

```text
Equal                  -> keyed equality index may narrow candidates
GreaterThan            -> scan
GreaterThanOrEqual     -> scan
LessThan               -> scan
LessThanOrEqual        -> scan
Between                -> scan
```

Rust enforcement occurs before persisted lookup: encrypted boxes retain only `CompareOp::Equal` index candidates.

The equality token must never be sorted or range-seeked as if its bytes represented semantic scalar order.

For mixed `AND`:

```text
status == active AND age >= 18
        |
        +--> equality token may narrow candidate record keys
                 |
                 v
            primary encrypted records
                 |
          authenticate/decrypt
                 |
          evaluate age >= 18
```

This preserves exact-match acceleration while adding no persisted order-revealing structure.

Decision record: `docs/ENCRYPTED_RANGE_DECISION_06.md`.

Regression guards: `rust/tests/encrypted_range_decision.rs` validates all five ordered/range operators and mixed equality+range AND semantics before/after encrypted index creation; `rust/tests/encrypted_range_planner_guard.rs` locks the equality-only encrypted planner rule.

## 11. Why encrypted range indexing is rejected for 0.6

Rejected designs:

- keyed hash/MAC ordering — incorrect because token order is unrelated to scalar order;
- plaintext/reversible sortable index bytes — violate the encrypted-index contract;
- order-preserving/order-revealing encryption — expands order/distribution leakage and cryptographic/durable-state complexity;
- bucketized range tokens — add leakage, false positives, boundary/versioning/storage complexity without demonstrated need.

A future milestone may revisit range indexing only with an explicit leakage budget and demonstrated production bottleneck.

## 12. Native profiles

Exactly three profiles remain:

```text
minimal
  CRUD + lifecycle + native watch

encryption
  minimal + encrypted create/open/read/write

full
  encryption + maintenance + query/index
```

Do not add a fourth profile for encrypted indexes or tuning.

## 13. Migration/interoperability

Core `dxtr_box` has no runtime Hive CE dependency.

Optional Hive CE migration flow:

```text
source enumeration/preflight
  -> key/value conversion
  -> collision detection
  -> destination reservation
  -> destination create/open
  -> one Box.putAll transaction
  -> close + release reservation
```

This path does not define product parity or 1.0 success.

## 14. FRB/package/native-size gates

Checked-in bindings are reproducible with FRB 2.8.0.

Package readiness:

```bash
make package-readiness
```

Native-size policy:

```text
allowed_growth = max(65,536 bytes, ceil(base_bytes * 3 / 100))
```

Minimal, encryption, and full are measured independently.

PR2's accepted BLAKE2 implementation kept full-profile Linux x64 growth inside policy at +30,432 bytes / +1.276%.

## 15. Staged consumers

`tool/validate_published_consumer.dart` validates the consumer-visible package payload on:

```text
Android
iOS
macOS
Linux
Windows
```

## 16. CI topology

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

Local cheap gate:

```bash
make preflight
```

Ready/non-draft work must satisfy full merge validation.

## 17. 0.6 sequence and closure

```text
PR1 — threat model + safe-default guard + docs: merged (#39)
PR2 — encrypted equality index + planner polish: merged (#40)
PR3 — encrypted range decision / scan-only guard: merged (#42)
PR4 — core reliability/API closure + 0.6 audit: active/final
```

PR4 is not a Hive/Hive CE parity pass. It intentionally avoids feature expansion and closes 0.6 only after the full merge quality bar validates the accepted runtime/security/compatibility matrix.

Closure record: `docs/RELEASE_AUDIT_06.md`.

## 18. Invariants to preserve

- Dart >=3.4 / Flutter >=3.22.
- FRB exactly 2.8.0.
- redb exactly 2.1.0.
- Native identity `rust_lib_dxtr_box`.
- Exactly three native profiles.
- `dxtr_box/1` remains readable.
- Primary data authoritative over indexes.
- No Dart whole-box cache.
- No implicit long-lived stale snapshot.
- Full encrypted authentication.
- No raw plaintext scalar values in encrypted index entries.
- Encrypted equality tokens are not range/order representations.
- Query/index/migration correctness.
- Native-size regression policy.
- Five-platform staged consumer builds.
- Full merge quality bar remains mandatory.

Important targets:

```bash
make preflight
make package-readiness
make frb-generate
make native-test
make hive-ce-migration-test
make query-index-test
make query-sort-test
make benchmark-query-index
make benchmark-comparison
make benchmark-read-path
make benchmark-batch-read
make native-size-regression
```

See `docs/QUERY_INDEX_ENCRYPTION_06.md` for the normative milestone contract, `docs/ENCRYPTED_RANGE_DECISION_06.md` for the encrypted range decision, `docs/RELEASE_AUDIT_06.md` for the final closure matrix, and `docs/PROJECT_HANDOFF.md` for current execution state.
