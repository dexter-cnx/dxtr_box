# Plaintext to Encrypted Migration

## Status

Implemented across the Rust storage engine and generated FRB boundary in PR #10. PR #11 completes the public `DxtrBox.encryptBox(...)` facade, native integration coverage, and documentation acceptance trail.

This document defines the shipped explicit migration contract for converting an existing plaintext dxtr_box file into an encrypted box. Migration is never triggered implicitly by `DxtrBox.open(..., encryptionKey: ...)`.

## Public contract

```dart
await DxtrBox.encryptBox(
  'settings',
  encryptionKey: 'correct horse battery staple',
);
```

All handles for the target box must be closed before calling the migration API.

## Preconditions

Migration rejects when:

- dxtr_box has not been initialized;
- the box name is invalid;
- the encryption key is empty;
- the box does not exist;
- the box has one or more live handles in the current process;
- the persisted box is already encrypted;
- the persisted storage format is unsupported;
- required encryption support is not compiled into the native library;
- the configured alternate/test native engine does not implement the optional `NativeEncryptionMigrationApi` capability.

The operation is intentionally maintenance-like. Callers must close all handles before migration.

## Atomicity model

The implementation uses an in-file redb write transaction over the existing `data` and `meta` tables.

Within the migration flow:

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

The value rewrites and final encryption metadata transition occur in one redb write transaction. No migration-visible encryption metadata change is committed before all values are ready to be rewritten successfully.

Legacy boxes without metadata may first receive the existing explicit plaintext metadata contract. That intermediate state is still a valid plaintext box and does not claim encryption.

## Failure and recovery semantics

Migration has only two intended externally observable durable states:

```text
before commit
  -> plaintext data + encryption_mode=none

after commit
  -> encrypted data + encryption_mode=chacha20poly1305 + salt + key_check
```

If encryption, MessagePack validation, allocation, redb writing, or another step fails before commit, the migration transaction is not committed and the original plaintext box remains valid.

If the process terminates before the redb migration transaction commits, redb recovery is expected to expose the pre-transaction plaintext state. If the process terminates after the migration API has returned successfully, reopening must require the new encryption key and all committed values must decrypt correctly.

The API does not claim durability for an operation that had not returned successfully before process termination.

The current automated suite directly verifies pre-commit validation failure safety and already has general process-kill recovery coverage for acknowledged plaintext/encrypted commits. A dedicated fault-injection test that deliberately kills a migration while its transaction is in-flight remains future hardening and is not claimed as completed coverage.

## Concurrency and lifecycle

Migration is exclusive per box.

The Rust API uses the same per-box mutation lock used by other native mutation/maintenance paths so migration cannot race another in-process mutation.

Migration rejects a box present in the native open-database registry. It does not invalidate or replace live `Arc<Database>` handles.

The Dart facade also rejects migration when `_openHandlesByName[name] > 0`, so callers receive a clear error before crossing FFI.

Cross-process exclusion remains delegated to redb/file locking behavior. If another process prevents the required access, migration must fail explicitly rather than retry indefinitely or partially rewrite data.

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

Legacy boxes without metadata resolve to the established explicit plaintext metadata contract before encryption. Migration does not invent a second legacy interpretation path.

## Watch semantics

Migration is a storage maintenance operation, not a logical user-data mutation stream.

Because live handles are forbidden, no `Box.watch()` subscribers may exist for the migrated box in the current process. Migration emits no synthetic put/clear events.

After migration, newly opened handles establish fresh metadata/watch state normally.

## Implemented test coverage

Rust coverage includes:

- plaintext box migrates successfully;
- keys and MessagePack values are preserved;
- reopening without a key fails after migration;
- reopening with the wrong key fails;
- reopening with the correct key succeeds;
- migrated stored values differ from original plaintext payloads;
- salt is present and has the expected length;
- empty key rejection;
- missing box rejection;
- already-encrypted box rejection;
- open-handle rejection;
- pre-commit validation failure leaves the original plaintext box readable.

Dart/native integration coverage includes:

- public `DxtrBox.encryptBox(...)` facade;
- Dart-side live-handle rejection;
- Dart -> FRB -> Rust migration of an existing plaintext box;
- correct-key reopen and wrong/missing-key rejection after migration;
- decoded data parity before vs after migration.

## Generated bindings

The migration function changes the FRB API surface. Generated files under `lib/src/rust/` and `rust/src/frb_generated.rs` were regenerated with Flutter Rust Bridge 2.8 and committed with PR #10.

CI now independently regenerates the bindings and fails on drift. Do not hand-edit generated FRB files to make a native API change appear complete.

## Non-goals

This migration path does not include:

- encrypted -> plaintext downgrade;
- encrypted -> new-key rotation;
- changing the storage format version;
- migrating Hive/Hive CE files;
- background migration while boxes are open;
- Dart 3.13 native tree shaking;
- query/index work.

Key rotation should be designed separately because it has different API and failure semantics even though it may reuse some rewrite machinery.

## Acceptance gate

The milestone is considered complete when PR #11 is green and merged because the following will then be true:

1. the explicit public Dart API exists;
2. the Rust migration is transactional;
3. generated FRB bindings are current and drift-checked;
4. Rust failure-safety and real Dart/native migration tests cover the shipped contract;
5. README, code walkthrough, testing docs, parity audit, and project handoff reflect the implementation;
6. the full CI and platform-build matrix are green.

Dedicated in-flight migration process-kill injection remains an additional hardening item, not a blocker for this milestone's current atomicity claim.
