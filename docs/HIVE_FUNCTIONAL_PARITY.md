# Hive Functional Parity Audit

## Goal

`dxtr_box` targets **functional replacement** of Hive / Hive CE for practical local NoSQL database workloads.

This does **not** mean source-level or drop-in API compatibility. Applications may need to change call sites, especially synchronous reads to asynchronous reads. The release criterion is that a workload reasonably implemented with Hive/Hive CE can be implemented with `dxtr_box` without losing an essential database capability.

## 1.0 release gate

`dxtr_box` must not be declared 1.0 stable until this audit is complete.

Every practical Hive/Hive CE capability must be classified as one of:

- `Exact` — equivalent user-visible capability and semantics.
- `Compatible` — same practical capability with a different API or implementation model.
- `Superseded` — dxtr_box provides a different mechanism that fully covers the practical use case.
- `Not applicable` — Hive-specific implementation detail with no user-facing capability loss.
- `Gap` — practical capability is still missing. Any `Gap` blocks the 1.0 functional-parity claim.

## Scope baseline

The audit baseline is current Hive CE functionality, including normal boxes, lazy boxes, isolate-aware access, box events, encryption, custom-object persistence, web storage, and lifecycle/maintenance operations.

The audit should be refreshed against the latest Hive CE release immediately before the 1.0 release candidate.

## Capability matrix

| Area | Hive/Hive CE capability | dxtr_box target | Status |
|---|---|---|---|
| Initialization | configurable storage path | `DxtrBox.init(path:)` | Implemented; final audit pending |
| Box lifecycle | open / close / delete / exists | equivalent lifecycle | Implemented; final audit pending |
| CRUD | put / get / delete | equivalent capability | Implemented; final audit pending |
| Batch writes | putAll / deleteAll | transactional batch operations | Implemented; final audit pending |
| Introspection | keys / values / length / isEmpty / containsKey | equivalent capability | In progress |
| Defaults | get with default value | equivalent capability | Implemented; final audit pending |
| Clear | clear entire box | one ACID write transaction | Implemented; final audit pending |
| Lazy access | values not retained wholesale in Dart RAM | native storage reads on demand; `lazy` semantics finalized before 1.0 | Gap |
| Events | `watch()` / key filtering | native Rust event broadcast exposed through FRB stream | Implemented; isolate semantics pending |
| Compaction | manual / strategy-driven compaction | explicit redb-backed `compact()` plus future policy | Compatible candidate; policy audit pending |
| Encryption | encrypted boxes | Argon2-derived key + ChaCha20Poly1305 authenticated values | Implemented; binary-size/audit gate pending |
| Encryption migration | plaintext box -> encrypted box | explicit transactional `DxtrBox.encryptBox()` | Implemented; dedicated interruption injection still future hardening |
| Custom values | TypeAdapter-backed objects | codegen-free structured codec / explicit serializer extension mechanism | Gap |
| Schema evolution | adapter-compatible model evolution | versioned codec/schema migration mechanism | Gap |
| Primitive coverage | null, bool, number, String, List, Map, binary, DateTime, etc. | MessagePack codec plus required additional built-ins | In progress |
| Sets / Duration | Hive CE built-ins | add codec support or equivalent representation | Gap |
| Object helpers | HiveObject save/delete relationships | ergonomic object/repository helper if practical use case warrants | Planned audit |
| Object references | HiveList/reference-style relationships | explicit reference/link mechanism or documented superseding pattern | Planned audit |
| Isolates | `IsolatedHive` | safe multi-isolate native database access and event behavior | Gap |
| Concurrent reads | supported access model | redb concurrent read transactions | Engine capability; Dart/isolate integration tests required |
| Write serialization | database-safe writes | redb ACID single-writer transaction model | Engine capability; broader concurrency tests required |
| Crash durability | persisted writes survive process failure | acknowledged-commit process-kill/reopen suite | Implemented foundation; broader soak/fault injection pending |
| Web | IndexedDB/Web/WASM support | IndexedDB fallback behind same Dart API | Gap |
| Flutter integration | Flutter initialization/helpers | dxtr_box Flutter facade | In progress |
| DevTools inspection | Hive CE Inspector | optional dxtr_box inspector/tooling; evaluate as parity requirement | Planned audit |
| Hive data migration | existing Hive data | `migrateFromHiveCe()` with documented supported types | Gap / planned 0.3 |
| Query/filter | app-side filtering | native query helpers + indexes where useful | Planned 0.3 |
| Binary size | pure-Dart Hive has no native payload | explicit native-size budget, Cargo profiles/features, future tree shaking | In progress / next milestone |

## Compatibility principle

API shape is allowed to differ when the architecture demands it.

Example:

```dart
// Hive-style in-memory read
final value = box.get('key');

// dxtr_box native storage read
final value = await box.get('key');
```

This is still `Compatible` if the application can perform the same database task safely and predictably.

Do not reintroduce whole-box Dart caching merely to imitate synchronous Hive reads.

## Custom object strategy

Hive CE supports custom classes through `TypeAdapter` and generated adapters. `dxtr_box` intentionally avoids requiring model code generation for basic usage.

Before 1.0, choose and validate a replacement strategy that covers the same practical workloads. Candidate mechanisms include:

1. built-in dynamic MessagePack values for maps/lists/primitives,
2. a small explicit serializer interface for domain objects,
3. version-tagged records for schema migration,
4. convenience adapters that are handwritten or runtime-registered rather than generated.

The final mechanism must support forward-compatible schema evolution and migration tests before custom-object parity is marked complete.

## Isolate and process semantics

Functional parity requires more than compiling from multiple isolates. Tests must verify:

- two Dart isolates can safely access the same box,
- reads do not corrupt or block unrelated readers,
- writes are serialized correctly,
- stale Dart metadata cannot overwrite native truth,
- watch events have documented cross-isolate behavior,
- close/delete/maintenance behavior is deterministic while other handles exist.

## Encryption parity gate

Before encryption can be marked fully audited:

- each encrypted box has a unique persisted random salt,
- Argon2 derives the encryption key,
- each value uses a unique nonce,
- ChaCha20Poly1305 authenticates ciphertext,
- record-key AAD prevents ciphertext swapping between keys,
- wrong passwords fail deterministically,
- tampered payloads are rejected,
- encrypted reopen and plaintext -> encrypted migration are tested,
- encryption-enabled binary size is measured separately.

The implementation now covers the storage/security behaviors above except the binary-size measurement gate and broader release-audit evidence.

## Plaintext -> encrypted migration contract

`DxtrBox.encryptBox()` is a storage-mode maintenance operation, distinct from future Hive-file migration.

Required semantics:

- never triggered implicitly by `open(..., encryptionKey: ...)`,
- requires all live handles for the box to be closed,
- validates all plaintext MessagePack payloads before committing the transition,
- rewrites values and changes encryption metadata in one redb write transaction,
- persists a fresh salt and authenticated key-check sentinel,
- rejects missing, open, already-encrypted, unsupported-format, or empty-key cases,
- successful reopen requires the new key and preserves decoded data.

A dedicated process-kill test that targets an in-flight migration remains future fault-injection hardening. The current contract relies on redb transactional before/after semantics plus tests that pre-commit validation failure preserves plaintext state.

## Hive migration parity gate

Future `migrateFromHiveCe()` must define support for at least:

- primitive values,
- lists/maps,
- binary data,
- DateTime,
- supported built-in extended values,
- custom objects through an explicit conversion callback where automatic conversion is impossible,
- encrypted-source migration with caller-supplied source credentials where technically feasible.

Hive data migration must be restart-safe or transactional enough that a failed migration cannot silently produce a partially valid destination.

## Performance is not parity

Functional parity does not require matching Hive's internal architecture or synchronous latency profile. Performance is evaluated separately.

Required benchmark dimensions before 1.0:

- cold open,
- random reads,
- sequential reads,
- single writes,
- batched writes,
- deletes,
- reopen persistence,
- memory usage with small and large boxes,
- database file size,
- encrypted vs unencrypted cost.

## Release checklist

Before 1.0 RC:

1. Refresh this matrix against the latest Hive CE public API and documentation.
2. Add tests for every row classified `Exact`, `Compatible`, or `Superseded` where automation is practical.
3. Resolve every practical capability still marked `Gap`.
4. Document intentional API/semantic differences in the migration guide.
5. Run migration tests using real Hive CE fixture databases.
6. Run Android, iOS, macOS, Linux, Windows, and Web validation.
7. Publish measured performance, memory, durability, and binary-size results.

Only after these gates pass may the project claim:

> `dxtr_box` is a functional replacement for Hive/Hive CE. Existing applications may need API changes, but practical Hive local-database workloads are covered.
