# Plaintext to Encrypted Migration

## Status

Active storage-hardening milestone.

This document defines the explicit migration contract for converting an existing plaintext dxtr_box file into an encrypted box. The migration must never be triggered implicitly by `DxtrBox.open(..., encryptionKey: ...)`.

## Public contract

The intended public API is an explicit operation on `DxtrBox`, conceptually:

```dart
await DxtrBox.encryptBox(
  'settings',
  encryptionKey: 'correct horse battery staple',
);
```

Final naming may change before release, but the semantics below are required.

## Preconditions

Migration must reject when:

- dxtr_box has not been initialized;
- the box name is invalid;
- the encryption key is empty;
- the box does not exist;
- the box has one or more live handles in the current process;
- the persisted box is already encrypted;
- the persisted storage format is unsupported;
- required encryption support is not compiled into the native library.

The operation is intentionally maintenance-like. Callers must close all handles before migration.

## Atomicity model

The preferred implementation is an in-file redb write transaction over the existing `data` and `meta` tables.

Within one write transaction:

1. Validate that the current persisted encryption mode is `none`.
2. Generate a fresh random per-box salt.
3. Derive the encryption key with Argon2.
4. Read every plaintext value from `data`.
5. Validate each value as MessagePack before rewriting it.
6. Encrypt every value with ChaCha20Poly1305 using a fresh nonce and the record key as AAD.
7. Replace each plaintext value with its encrypted representation.
8. Write `encryption_mode = chacha20poly1305`.
9. Persist the salt.
10. Persist the encrypted key-check sentinel.
11. Commit once.

No migration-visible metadata change may be committed before all values have been rewritten successfully.

## Failure and recovery semantics

The migration must have only two externally observable durable states:

```text
before commit
  -> plaintext data + encryption_mode=none

after commit
  -> encrypted data + encryption_mode=chacha20poly1305 + salt + key_check
```

If encryption, MessagePack validation, allocation, redb writing, or any other step fails before commit, the transaction must be aborted and the original plaintext box must remain valid.

If the process is terminated before commit, redb recovery must expose the original plaintext state.

If the process terminates after commit returns successfully, reopening must require the new encryption key and all committed values must decrypt correctly.

The API must not claim durability for an operation that had not returned successfully before process termination.

## Concurrency and lifecycle

Migration is exclusive per box.

The native API must use the same per-box mutation lock used by open/close/delete/compact paths so the migration cannot race another mutation in-process.

Migration must reject a box present in the native open-database registry. It must not silently invalidate or replace live `Arc<Database>` handles.

The Dart facade must also reject migration when `_openHandlesByName[name] > 0` so callers receive an early, clear error before crossing FFI.

Cross-process exclusion remains delegated to redb/file locking behavior. If another process has the database open in a way that prevents exclusive write access, migration must fail explicitly rather than retry indefinitely or partially rewrite data.

## Storage-format rules

Plaintext source metadata:

```text
format_version  = dxtr_box/1
encryption_mode = none
```

Encrypted destination metadata:

```text
format_version   = dxtr_box/1
encryption_mode  = chacha20poly1305
encryption_salt  = 16 random bytes
key_check         = encrypted known sentinel
```

Legacy boxes without metadata should first resolve to the established explicit plaintext metadata contract. Migration must not invent a second legacy interpretation path.

## Watch semantics

Migration is a storage maintenance operation, not a logical user-data mutation stream.

Because live handles are forbidden, no `Box.watch()` subscribers may exist for the migrated box in the current process. Migration therefore emits no synthetic put/clear events.

After migration, newly opened handles establish a fresh metadata/watch state normally.

## Test requirements

Rust tests must cover at least:

- plaintext box migrates successfully;
- all keys and MessagePack values are preserved;
- reopening without a key fails after migration;
- reopening with the wrong key fails;
- reopening with the correct key succeeds;
- migrated values are not present as plaintext on disk;
- salt is present and has the expected length;
- key-check is present and authenticates the requested password;
- empty key rejection;
- missing box rejection;
- already-encrypted box rejection;
- open-handle rejection;
- unsupported-format rejection;
- injected/pre-commit failure leaves the original plaintext box readable;
- process-kill before acknowledged commit recovers the original plaintext state where practical;
- process-kill after acknowledged commit recovers the encrypted state where practical.

Dart/native integration tests must cover at least:

- `DxtrBox` explicit migration facade;
- Dart-side live-handle rejection;
- Dart -> FRB -> Rust migration of an existing plaintext box;
- correct-key reopen and wrong/missing-key rejection after migration;
- data parity before vs after migration.

## Generated bindings

Adding the migration function changes the FRB API surface. Generated files under `lib/src/rust/` must be regenerated with the checked-in FRB 2.8 workflow and committed in the same PR.

Do not hand-edit generated FRB files to make migration appear complete.

## Non-goals for this milestone

This milestone does not include:

- encrypted -> plaintext downgrade;
- encrypted -> new-key rotation;
- changing the storage format version;
- migrating Hive/Hive CE files;
- background migration while boxes are open;
- Dart 3.13 native tree shaking;
- query/index work.

Key rotation should be designed separately because it has different API and failure semantics even though it may reuse some rewrite machinery.

## Acceptance gate

The milestone is complete only when:

1. the explicit Dart API exists;
2. the Rust migration is transactional;
3. generated FRB bindings are refreshed;
4. unit/native/process-boundary tests cover the failure model;
5. README, code walkthrough, testing docs, and project handoff reflect the shipped contract;
6. the full CI and platform-build matrix are green.
