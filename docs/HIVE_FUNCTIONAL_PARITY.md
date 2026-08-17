# Hive / Hive CE Compatibility Reference

> **Historical/reference document — not a product roadmap or 1.0 release gate.**
>
> Dxtr_Box is a native local database for Flutter. It is **not** positioned as a Hive/Hive CE replacement and does not require feature-by-feature Hive parity for 1.0. Hive CE remains useful as an optional migration source, compatibility reference, and benchmark peer.

## Purpose

This document preserves the older Hive-oriented capability audit as a **compatibility inventory**. It can help when migrating an existing Hive/Hive CE application or comparing practical local-database capabilities, but gaps listed here do not automatically become Dxtr_Box product requirements.

A capability should be implemented only when it independently strengthens Dxtr_Box or is required by an explicit interoperability/migration contract.

## Classification

When comparing a Hive/Hive CE workload with Dxtr_Box, use these descriptive labels only:

- `Exact` — equivalent user-visible capability and semantics.
- `Compatible` — same practical capability with a different API or implementation model.
- `Superseded` — Dxtr_Box provides a different mechanism covering the practical use case.
- `Not applicable` — Hive-specific behavior that is not part of the Dxtr_Box product model.
- `Gap` — a capability an application may need when migrating from Hive/Hive CE; **not automatically a Dxtr_Box roadmap commitment**.

## Compatibility inventory

| Area | Hive/Hive CE capability | Dxtr_Box position | Status / note |
|---|---|---|---|
| Initialization | configurable storage path | `DxtrBox.init(path:)` | Implemented |
| Box lifecycle | open / close / delete / exists | equivalent lifecycle | Implemented |
| CRUD | put / get / delete | asynchronous native-backed operations | Implemented |
| Batch writes | putAll / deleteAll | transactional batch operations | Implemented |
| Introspection | keys / values / length / isEmpty / containsKey | native-backed equivalents where exposed | Compatibility inventory |
| Defaults | get with default value | equivalent capability | Implemented |
| Clear | clear entire box | one ACID write transaction | Implemented |
| Lazy access | lazy box semantics | native storage reads are already on-demand; no Hive-style LazyBox contract required | Not a parity gate |
| Events | `watch()` / key filtering | native Rust event broadcast through FRB stream | Implemented foundation |
| Compaction | manual / strategy-driven compaction | explicit redb-backed `compact()` | Compatible |
| Encryption | encrypted boxes | Argon2 + ChaCha20Poly1305 authenticated storage | Implemented |
| Encryption migration | plaintext -> encrypted | explicit transactional migration | Implemented |
| Custom values | TypeAdapter-backed objects | codegen-free dynamic values; optional typed/serializer ergonomics may evolve independently | Product decision, not parity gate |
| Schema evolution | adapter/model evolution | no general schema framework currently required | Deferred unless product evidence justifies it |
| Primitive coverage | common primitive/list/map/binary/date values | MessagePack dynamic codec | Compatibility inventory |
| Sets / Duration | Hive CE built-ins | represent explicitly or add codec support when independently useful | Optional |
| Object helpers | HiveObject helpers | application/repository layer concern unless a strong generic use case emerges | Not a parity gate |
| Object references | HiveList/reference-style relations | application-level references unless Dxtr_Box later adopts a native relation feature | Not a parity gate |
| Isolates | `IsolatedHive` | native database access/concurrency semantics should be validated on their own merits | Reliability candidate |
| Concurrent reads | supported access model | redb concurrent read transactions | Engine capability |
| Write serialization | database-safe writes | redb ACID single-writer transaction model | Engine capability |
| Crash durability | persisted writes survive failure | process-kill/reopen durability coverage | Implemented foundation |
| Web | IndexedDB/Web support | no current Web strategy | Deferred product/platform decision |
| Flutter integration | Flutter initialization/helpers | Flutter FFI plugin facade | Implemented |
| DevTools inspection | Hive inspector | optional tooling opportunity | Not a release gate |
| Hive data migration | existing Hive data | `migrateFromHiveCe()` for documented supported types | Implemented interoperability path |
| Query/filter | mostly app-side filtering | native query engine + persisted indexes | Dxtr_Box-specific capability |
| Binary size | pure-Dart baseline | explicit native-size profiles/regression policy | Dxtr_Box-specific constraint |

## Compatibility principle

API shape may differ when the architecture demands it.

```dart
// Hive-style in-memory read
final value = box.get('key');

// Dxtr_Box authoritative native-storage read
final value = await box.get('key');
```

A migration can still be practical even when call sites change. Do not reintroduce a whole-box Dart cache merely to imitate Hive synchronous reads.

## Hive CE migration contract

The supported interoperability path is documented in `HIVE_CE_MIGRATION_03.md`.

The current migration foundation covers documented primitive/container values, binary data, DateTime, deterministic key conversion, caller-supplied conversion for unsupported custom values, encrypted source/destination scenarios, preflight collision/value validation, and exclusive destination reservation.

LazyBox migration, direct `.hive` parsing, merge/overwrite into an existing destination, and unrestricted custom-object/schema migration are not implied product requirements. They should be added only under an explicit migration use case.

## Encryption comparison notes

Dxtr_Box encryption requirements are defined by its own security contract rather than Hive parity. Current invariants include:

- per-box persisted random salt;
- Argon2-derived key material;
- unique nonces for encrypted values;
- ChaCha20Poly1305 authenticated encryption;
- authenticated record-key binding;
- deterministic wrong-key/tamper rejection;
- explicit plaintext-to-encrypted migration;
- native-size measurement by capability profile.

Encrypted query/index behavior is defined separately in `QUERY_INDEX_ENCRYPTION_06.md` and `ENCRYPTED_RANGE_DECISION_06.md`.

## Performance comparison

Performance comparison with Hive CE is useful engineering evidence but not a parity requirement. The broader comparison harness also includes other local-database engines and separates correctness from diagnostic timing.

Relevant targets include:

```bash
make benchmark-comparison-correctness
make benchmark-comparison
make benchmark-query-index
```

Hosted-runner timings are diagnostic only.

## 1.0 direction

Dxtr_Box 1.0 should represent a coherent, production-ready **Dxtr_Box contract**: durable native storage, understandable public API, query/index semantics, authenticated encryption, compatibility/migration behavior, and reliable five-platform packaging.

It is **not** blocked on reproducing every Hive/Hive CE feature. Any future Hive-oriented work must be justified as migration/interoperability value or as an independently useful Dxtr_Box capability.
