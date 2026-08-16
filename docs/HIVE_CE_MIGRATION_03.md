# dxtr_box 0.3 Hive CE migration

## Goal

Provide a safe, explicit migration path from an already-open Hive CE box into a new dxtr_box destination without reverse-engineering Hive CE storage files.

## Source contract

- Source data is read through the public Hive CE API (`Box<dynamic>`), using Hive CE 2.19.x as the current compatibility baseline.
- Encrypted Hive CE sources are opened by the caller with the appropriate Hive CE cipher/credentials before migration; the migration API never handles or stores source secrets itself.
- Normal Hive CE boxes are supported in the first 0.3 slice. LazyBox support is deferred until the same atomic destination contract can be preserved without loading every value eagerly.
- Custom Hive objects require an explicit value conversion callback unless their runtime value is already accepted by `DxtrCodec`.

## Destination contract

Migration targets a **new** dxtr_box box name. Existing destinations are rejected in 0.3 rather than providing a non-atomic overwrite mode.

The migration pipeline is:

```text
open Hive CE source
  -> enumerate source keys deterministically
  -> convert Hive keys to dxtr string keys
  -> convert values where required
  -> DxtrCodec preflight every converted value
  -> detect key collisions before touching destination
  -> create/open new dxtr destination
  -> one `putAll` call / one native write transaction for all migrated entries
  -> close destination
  -> return migration result
```

No source entry is deleted or modified.

## Key conversion

Hive CE allows String and int keys while dxtr_box currently uses String keys.

Default conversion:

- String Hive keys are preserved exactly.
- int Hive keys become `@hive-int:<decimal>`.
- any other key type is rejected unless the caller provides a key converter.
- converted-key collisions are detected before destination creation and fail the migration.

The reserved int prefix is intentionally explicit so automatic Hive keys do not silently become indistinguishable from ordinary numeric-looking String keys.

## Value conversion

Values supported directly by `DxtrCodec` pass through unchanged. Unsupported/custom values require a caller conversion callback.

The callback receives the Hive key and value so applications can map generated TypeAdapter objects into stable map/list/primitive representations.

All converted values are encoded during preflight before any destination data write. A conversion/encoding failure therefore cannot leave a partially populated destination.

## Failure and restart behavior

0.3 guarantees **no partially populated destination transaction**: all migrated entries are submitted in one native `putAll` transaction after full Dart-side preflight.

If destination opening succeeds but the process terminates before the single `putAll` commit, an empty destination file may exist. This is not considered a completed migration and must be handled explicitly by the caller/retry flow. The migration API must never silently overwrite an existing destination.

A future stronger crash-atomic contract may use native staging + file promotion if product evidence justifies it.

## Result

The public result reports:

- source box name
- destination box name
- migrated entry count
- number of String keys
- number of int keys converted with the default policy

## Validation gate

The implementation is not complete until tests cover:

- real Hive CE fixture box with primitives, lists/maps, binary, and DateTime
- String and int key migration
- collision rejection
- destination-already-exists rejection
- unsupported/custom value rejection without converter
- custom value conversion callback
- encrypted destination migration
- encrypted Hive CE source opened with caller-supplied Hive CE credentials
- source remains unchanged
- failed preflight does not create/populate destination
- minimum Flutter/Dart SDK compatibility

## Non-goals for 0.3

- parsing `.hive` files directly
- source deletion
- implicit migration during `DxtrBox.open`
- LazyBox migration
- source schema evolution automation
- TypeAdapter introspection/code generation
- overwrite/merge into an existing dxtr_box destination
