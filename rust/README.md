# rust_lib_dxtr_box

Rust-native frontend and shared storage engine for [`dxtr_box`](https://github.com/dexter-cnx/dxtr_box), backed by redb.

The crate exposes the same authoritative Rust core used by the Flutter/Dart package. It does not wrap Dart or Flutter and uses the same durable `dxtr_box/1` storage contract.

## Native profiles

- default / `full`: CRUD, lifecycle, watch, encryption, maintenance, query, and index support
- `encryption`: core CRUD/lifecycle/watch plus encrypted open/create
- `--no-default-features`: minimal core CRUD/lifecycle/watch

Exactly these three supported profiles are part of the project compatibility policy.

## Compatibility

`rust_lib_dxtr_box` 1.1.0 corresponds to the `dxtr_box` 1.1 stable line. The durable format remains `dxtr_box/1`.

See the repository README and `docs/PROJECT_HANDOFF.md` for architecture, guarantees, benchmarks, and release policy.

## License

MIT
