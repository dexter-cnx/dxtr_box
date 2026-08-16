# dxtr_box 0.3 Hive CE migration

## Goal

Provide a safe, explicit migration path from an already-open Hive CE box into a new dxtr_box destination without reverse-engineering Hive CE storage files or forcing Hive CE onto every dxtr_box consumer.

## Dependency boundary

The core `dxtr_box` package deliberately has **no runtime dependency on Hive CE**. This preserves the package minimum of Dart 3.4 / Flutter 3.22 and avoids requiring applications that never used Hive CE to install it.

Migration receives a `HiveCeMigrationSource`, a small callback adapter around an already-open Hive CE box. Compatibility is validated against a separate fixture package pinned to Hive CE 2.19.3 under `tool/hive_ce_migration_fixture/`.

Typical adapter:

```dart
final source = HiveCeMigrationSource(
  name: hiveBox.name,
  isOpen: () => hiveBox.isOpen,
  keys: () => hiveBox.keys,
  get: hiveBox.get,
);
```

## Source contract

- The application opens the Hive CE source with Hive CE itself, then wraps it in `HiveCeMigrationSource`.
- Hive CE 2.19.3 is the current tested compatibility baseline.
- Encrypted Hive CE sources are opened by the caller with the appropriate Hive CE cipher/credentials before migration; dxtr_box never receives or stores source secrets.
- Normal Hive CE boxes are covered in 0.3. LazyBox migration is deferred.
- The source remains open, authoritative, and unmodified throughout migration.
- Custom Hive values require an explicit `valueConverter` unless their runtime value is already accepted by `DxtrCodec`.

## Destination contract

Migration targets a **new** dxtr_box box name. Existing destinations are rejected rather than merged or overwritten.

The migration pipeline is:

```text
already-open Hive CE box
  -> HiveCeMigrationSource callbacks
  -> enumerate source keys
  -> convert Hive keys to dxtr string keys
  -> convert unsupported values when required
  -> DxtrCodec preflight every converted value
  -> detect converted-key collisions
  -> atomically reserve {destination}.dxtr with exclusive file creation
  -> open the reserved dxtr destination
  -> one Box.putAll call
  -> one native redb write transaction for migrated entries
  -> close destination
  -> return HiveCeMigrationResult
```

The exclusive reservation is the create-if-absent boundary for migration. Concurrent migrations targeting the same destination cannot both proceed: exactly one obtains the filesystem reservation and the other fails without opening or mutating that destination.

No source entry is deleted or modified.

## Key conversion

Hive CE allows String and int keys while dxtr_box currently uses String keys.

Default conversion:

- String Hive keys are preserved exactly.
- int Hive keys become `@hive-int:<decimal>`.
- any other key type is rejected unless `keyConverter` maps it to a non-empty String.
- converted-key collisions are detected before destination creation and fail the migration.

The explicit int prefix prevents automatic Hive keys from silently colliding with ordinary numeric-looking String keys. A source String key that already equals a converted int key is also treated as a collision.

## Value conversion

Values directly supported by `DxtrCodec` pass through unchanged:

```text
null
bool
int
double
String
Uint8List
DateTime
List
Map<String, dynamic>
```

Unsupported/custom values require `valueConverter(dynamic value)`. The converted value is recursively normalized and must itself become codec-supported. Returning the same unsupported instance is rejected.

All converted values are encoded during preflight before destination reservation. A conversion/encoding failure therefore does not create or partially populate the destination.

## Failure and restart behavior

0.3 guarantees **no partially populated committed migration transaction**: all prepared entries are submitted in one native `putAll` write transaction after full Dart-side preflight.

If destination handle initialization fails after the exclusive reservation is created, the reservation owned by that migration is closed/deleted before the original error is rethrown. If `putAll` throws after the destination was successfully opened, migration closes and deletes the newly-created destination before rethrowing.

A process termination after exclusive reservation but before the single `putAll` commit may still leave an empty destination file. That is not a completed migration and callers must handle it explicitly before retrying. A future stronger crash-atomic design could use native staging + promotion if product evidence justifies the extra storage machinery.

## Result

`HiveCeMigrationResult` reports:

- `sourceName`
- `destinationName`
- `entriesMigrated`

No key-type counters are currently part of the public result.

## Validation gate

The Hive CE 2.19.3 fixture suite covers:

- primitives, lists/maps, `Uint8List`, and `DateTime`;
- String and int keys;
- default int-key mapping;
- converted-key collision rejection before destination creation;
- unsupported/custom value rejection without a converter;
- custom value conversion using `BigInt` as a real unsupported Hive CE value;
- destination-already-exists rejection without mutation;
- concurrent migration attempts to one destination with exactly one winner;
- encrypted Hive CE source opened with caller-supplied Hive CE credentials;
- encrypted dxtr_box destination;
- source preservation;
- failed preflight leaving no destination;
- destination reservation cleanup when handle initialization fails;
- root package minimum Flutter/Dart compatibility independently from the Hive CE fixture package.

Run:

```bash
make hive-ce-migration-test
```

CI runs the fixture package separately so Hive CE 2.19.3 cannot accidentally raise the core package SDK floor.

## Non-goals for 0.3

- parsing `.hive` files directly;
- source deletion;
- implicit migration during `DxtrBox.open`;
- LazyBox migration;
- source schema evolution automation;
- TypeAdapter introspection/code generation;
- overwrite/merge into an existing dxtr_box destination;
- adding Hive CE as a core dxtr_box dependency.