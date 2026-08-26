# Dxtr_Box 1.2 Inspector CLI

## Status

Milestone: 1.2
Issue: #95
Release target: 1.2.0

The 1.2 milestone adds a read-only Inspector CLI for existing `dxtr_box/1` databases. It reuses the authoritative Rust storage/core implementation and does not define a parallel durable-format parser.

## Command surface

```text
dxtr-box-inspect --help
dxtr-box-inspect --version
dxtr-box-inspect <path> boxes [--format text|json]
dxtr-box-inspect <path> keys <box> [--offset N] [--limit N] [--format text|json]
dxtr-box-inspect <path> get <box> <key> [--raw] [--key-stdin] [--format text|json]
dxtr-box-inspect <path> indexes <box> [--format text|json]
```

`text` is the default. JSON output is deterministic and stdout is reserved for requested data; diagnostics go to stderr.

## Read-only implementation

redb 2.1.0 does not expose a read-only database-open type suitable for this contract. Inspector commands therefore use a snapshot-copy seam:

1. validate the requested base directory and box;
2. open the original `.dxtr` only through ordinary filesystem read operations;
3. copy it to a unique temporary snapshot;
4. open the temporary copy with redb;
5. perform read transactions only;
6. close and remove the temporary snapshot on drop.

The normal runtime `db::open` path is intentionally not used because it may create/repair metadata or ensure tables. Tests assert byte-for-byte source invariance for representative plaintext and encrypted reads.

## Record decoding

In the default/full profile, `get` semantically decodes persisted MessagePack using BoxCodec wire semantics, including:

- `@dxtr:map` -> JSON object;
- `@dxtr:list` -> JSON array;
- `@dxtr:bytes` -> `{ "$dxtrType": "bytes", "data": [...] }`;
- `@dxtr:datetime` -> `{ "$dxtrType": "datetime", "microsecondsSinceEpoch": ..., "isUtc": true }`.

`--raw` bypasses semantic decoding and returns the exact persisted record bytes. For plaintext boxes those bytes are the persisted MessagePack payload. For encrypted boxes they remain the stored nonce + ChaCha20Poly1305 ciphertext/authentication data and are **not** MessagePack until successfully decrypted through normal semantic `get` with `--key-stdin`.

## Encryption and key input

Encrypted records use the same Argon2 + ChaCha20Poly1305 primitives and record-key AAD as the runtime core.

`--key-stdin` is the supported secret channel. It reads exact UTF-8 input from stdin and does not trim CR/LF. A trailing newline is therefore part of the key. Prefer `printf` when the key must not contain a newline:

```bash
printf %s 'secret' | dxtr-box-inspect ./data get secure token --key-stdin --format json
```

Key material is not accepted as a command-line value and is never echoed in normal output or diagnostics.

## Pagination

`keys` is deterministic and bounded. `limit` must be between 1 and 1000 inclusive. Pagination uses `offset` plus bounded traversal and does not intentionally materialize the entire box for a small page.

## Exit codes

- `0`: success
- `1`: unexpected internal failure
- `2`: CLI usage/argument error
- `3`: database path/open failure
- `4`: requested box/key not found
- `5`: decode/authentication failure
- `6`: unsupported capability/profile/format

## Packaging

The Rust crate declares:

```toml
[[bin]]
name = "dxtr-box-inspect"
path = "src/bin/dxtr_box_inspect.rs"
```

Repository checkout installation:

```bash
cargo install --path rust --bin dxtr-box-inspect
```

After crates.io publication of 1.2.0:

```bash
cargo install rust_lib_dxtr_box --version 1.2.0 --bin dxtr-box-inspect
```

## Compatibility boundary

1.2.0 keeps unchanged:

- durable format `dxtr_box/1`;
- Dart >= 3.4;
- Flutter >= 3.22;
- flutter_rust_bridge 2.8.0;
- redb 2.1.0;
- native profiles exactly `minimal | encryption | full`;
- no mandatory async runtime.

The milestone adds no TUI, mutation/edit/import command, storage migration, ORM/codegen layer, synchronization layer, GPUI dependency, Tokio commitment, or fourth native profile.

## Release gates

Before publication, the release candidate must pass repository CI including format/clippy/tests, all three Rust profiles, native integration, package/crate readiness, pub dry-run, cross-frontend compatibility, staged platform consumers, concurrency evidence, and Inspector read-only/decoding regressions.
