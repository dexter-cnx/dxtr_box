# Dxtr_Box 0.9 — Config Fingerprint Decision

## Decision

Do **not** persist a schema/index configuration fingerprint in PR2.

Dxtr_Box currently has no declarative schema-registration or desired-index manifest at open time. Persisted `index_definitions` are already the authoritative durable configuration. Hashing those definitions and storing the hash beside them would only duplicate state that was read from the same source and would not, by itself, remove any startup work.

A fingerprint becomes useful only when there are two independently meaningful states to compare, for example:

```text
expected configuration supplied by the consumer
                  vs
configuration last reconciled into durable storage
```

That contract does not exist today, and adding it only to justify a fingerprint would violate the dynamic-first API direction.

## Current startup path

Opening an existing box performs bounded metadata checks:

1. open the redb database;
2. ensure the primary/meta tables are available;
3. resolve format metadata:
   - for boxes that already contain `meta[format_version]`, verify the stored value is exactly `dxtr_box/1`;
   - for legacy plaintext boxes that predate format metadata, initialize the missing metadata as `dxtr_box/1` rather than pretending an existing value was validated;
4. resolve and validate encryption metadata/key state;
5. under reduced profiles, reject boxes that contain persisted indexes;
6. under `full`, ensure the existing index-definition/index-entry tables exist.

The legacy metadata-initialization path is an explicit compatibility behavior that any future startup optimization must preserve. A fast path must not skip validation when a format value already exists, and it must not break the supported initialization path for legacy boxes whose format metadata is absent.

There is currently no schema scan, model registration pass, automatic index declaration pass, or index rebuild/reconciliation pass on every open.

Because of that, a persisted fingerprint would not currently skip material reconciliation work.

## Correctness guard

`rust/tests/config_fingerprint_decision.rs` locks in the behavior a future optimization must preserve through both supported frontends:

- boxes start with no index declarations unless the consumer creates them;
- index configuration can be created dynamically at runtime;
- index definitions survive close/reopen;
- index definitions can be dropped dynamically;
- the dropped state survives another reopen;
- Rust-native and FRB-adapter paths observe the same durable configuration.

The test intentionally does not depend on any fingerprint key or table. It protects semantics rather than an implementation detail.

## Why a tautological fingerprint is rejected

A design such as:

```text
fingerprint = hash(sorted(index_definitions))
store fingerprint next to index_definitions
```

has no useful independent comparison target during open. To trust the fingerprint, the runtime either has to:

- read the definitions anyway and recompute it, which saves nothing material; or
- trust the stored hash without recomputing it, which says nothing about an externally desired configuration and therefore cannot safely skip work that does not already exist.

It also introduces a second durable representation that must be updated transactionally on create/drop and repaired after older-version opens, increasing complexity without demonstrated startup benefit.

## Revisit criteria

A persisted configuration fingerprint may be reconsidered only if at least one of these becomes true:

1. a real consumer-supplied desired-index/config manifest is introduced while dynamic APIs remain first-class;
2. profiling identifies a concrete startup reconciliation pass whose cost grows materially with configuration size;
3. a downstream frontend needs deterministic configuration negotiation across process/runtime boundaries;
4. another independently authoritative configuration source exists and a fingerprint can cheaply prove equality with durable state.

Any future fingerprint must still satisfy:

- deterministic, versioned canonical input encoding;
- no skipping of existing-format validation or the supported legacy metadata-initialization path;
- no skipping of encryption/key validation;
- mismatch/unknown-version fallback to authoritative reconciliation;
- transactional updates with the configuration they summarize;
- compatibility with old boxes that have no fingerprint metadata;
- cross-frontend conformance tests;
- measured cold-open/reopen benefit before performance claims.

## PR3 consequence

PR3 should benchmark the existing cold-open/reopen path before adding runtime machinery. If open/reopen is already small and does not scale materially with record count or index count, 0.9 should record an evidence-backed **no fast-path implementation** rather than add speculative metadata.

This is a maturity decision, not a dropped feature: the optimization remains available when a real comparison target and measurable startup cost exist.
