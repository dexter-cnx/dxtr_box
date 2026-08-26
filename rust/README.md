# rust_lib_dxtr_box

Rust-native frontend and shared storage engine for [`dxtr_box`](https://github.com/dexter-cnx/dxtr_box), backed by redb.

The crate exposes the same authoritative Rust core used by the Flutter/Dart package. It does not wrap Dart or Flutter and uses the same durable `dxtr_box/1` storage contract.

## Native profiles

- default / `full`: CRUD, lifecycle, watch, encryption, maintenance, query, index support, and semantic Inspector decoding
- `encryption`: core CRUD/lifecycle/watch plus encrypted open/create
- `--no-default-features`: minimal core CRUD/lifecycle/watch

Exactly these three supported profiles are part of the project compatibility policy.

## Inspector CLI

The crate ships the read-only `dxtr-box-inspect` binary. Install it from crates.io after 1.2.0 is published:

```bash
cargo install rust_lib_dxtr_box --version 1.2.0 --bin dxtr-box-inspect
```

For a repository checkout:

```bash
cargo install --path rust --bin dxtr-box-inspect
```

Example:

```bash
dxtr-box-inspect ./data boxes
dxtr-box-inspect ./data keys settings --offset 0 --limit 100
dxtr-box-inspect ./data get settings theme --format json
printf %s 'secret' | dxtr-box-inspect ./data get secure token --key-stdin --format json
```

`get` performs semantic BoxCodec-compatible decoding in the default/full profile. `--raw` bypasses decoding and returns exact persisted record bytes: plaintext records contain persisted MessagePack, while encrypted records remain nonce + ChaCha20Poly1305 ciphertext/authentication data. `--key-stdin` consumes exact UTF-8 input; trailing newlines are significant.

## Compatibility

`rust_lib_dxtr_box` 1.2.0 corresponds to the `dxtr_box` 1.2 stable line. The durable format remains `dxtr_box/1`; Dart/Flutter SDK floors, FRB 2.8.0, redb 2.1.0, and the three-profile policy are unchanged.

See the repository README, `docs/INSPECTOR_CLI_12.md`, and `docs/PROJECT_HANDOFF.md` for architecture, guarantees, and release policy.

## License

MIT
