# Native feature profiles and binary-size baseline

This document defines the supported Rust feature profiles used to control native payload size without changing the public Dart/Flutter SDK floor.

## Profiles

### minimal

Build command:

```text
cargo build --manifest-path rust/Cargo.toml --release --no-default-features
```

Includes:

- redb storage;
- core CRUD and batch operations;
- box lifecycle;
- native watch registration and event delivery required by the current Dart `Box` lifecycle.

Does not include encryption dependencies. Maintenance entry points remain present at the FRB ABI boundary but fail explicitly when their required native feature is unavailable.

### encryption

Build command:

```text
cargo build --manifest-path rust/Cargo.toml --release --no-default-features --features encryption
```

Includes everything in `minimal`, plus:

- Argon2 key derivation;
- ChaCha20Poly1305 value encryption;
- encrypted box create/open/read/write support.

It intentionally does not enable maintenance operations. Plaintext-to-encrypted migration and compaction are not part of this profile.

### full

Build command:

```text
cargo build --manifest-path rust/Cargo.toml --release
```

`full` is the default feature profile and includes:

- `encryption`;
- `maintenance`;
- current production behavior including compaction and plaintext-to-encrypted migration.

Keeping `full` as the default preserves existing package behavior for normal Cargokit/Flutter builds.

## Why watch is not optional yet

The public Dart `DxtrBox.open()` lifecycle registers a native watcher before metadata hydration. Removing watch support from a reduced native build would make the normal public `Box` API unusable rather than merely disabling an optional capability.

Watch can become independently optional only after the Dart lifecycle has an explicit profile-aware path that does not depend on native watch registration.

## Maintenance capability behavior

Reduced profiles must fail explicitly, never silently no-op:

- `compact()` without `maintenance` returns a native feature-required error;
- plaintext-to-encrypted migration requires both `encryption` and `maintenance`.

Encrypted box create/open remains available in the `encryption` profile even though migration is unavailable.

## Reproducible size measurement

Run:

```text
make native-size-baseline
```

The harness builds each profile into an isolated `CARGO_TARGET_DIR` and records the release dynamic-library size in:

```text
build/native-size/native-size-baseline.tsv
```

The result includes:

- git commit;
- OS;
- architecture;
- rustc version;
- cargo version;
- profile;
- exact artifact path;
- artifact bytes.

The CI size job publishes only `build/native-size/native-size-baseline.tsv` as the retained artifact; isolated Cargo target directories are deliberately not uploaded. These measurements are informational only. There is no regression threshold until repeated measurements are shown to be stable enough across a controlled runner/toolchain.

### Validated Linux x86_64 baseline

PR #12 CI #144 validated the three release profiles on Linux x86_64 with the same runner/toolchain and isolated target directories:

| Profile | Bytes | Delta vs minimal |
| --- | ---: | ---: |
| minimal | 1,893,736 | baseline |
| encryption | 1,992,296 | +98,560 (+5.2%) |
| full | 2,032,312 | +138,576 (+7.3%) |

These are native dynamic-library measurements for that Linux x86_64 CI environment only. They are not cross-platform package-size claims.

## Current scope

The first automated baseline is Linux x86_64 because it provides a deterministic same-run comparison across all three profiles. Additional per-platform baselines should use the same profile definitions and record target triple/build metadata before any cross-platform size claim is made.

Dart 3.13 recorded-use/native tree shaking remains outside this milestone. Cargo profile measurements establish the baseline required before that optimization is reconsidered.
