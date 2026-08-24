# 0.10 Real-world Cross-frontend Evidence

This milestone compares two frontends that target the same authoritative Rust/redb engine:

- `dart_frb`: Dart API through flutter_rust_bridge
- `rust_native`: public Rust-native API directly

The evidence is diagnostic, not a leaderboard. Differences include frontend boundary cost, encoding/decoding work, and runner/build configuration. Do not interpret the ratio as a storage-engine speed claim.

## Scenario parity

Both runners exercise the same three workload families:

1. `settings_session`: repeated point reads plus overwrite-heavy active-workspace updates.
2. `catalog_workspace`: deterministic hot batch reads plus point-read/update work, with retention deletion measured outside the timing samples.
3. `activity_event`: bounded hot reads over the newest events, with retention deletion measured outside the timing samples.

Every timing sample within one scenario uses the same operation mix. Both runners report `operations_per_sample` in `logical_records` and keep deletion counts explicitly untimed.

## Correctness requirements

Timing evidence is accepted only after the runner validates the applicable storage contracts:

- settings overwrite resolves to the latest value;
- catalog batch reads return the full requested hit set in input order;
- catalog records preserve expected identifiers;
- configured catalog deletion keys are absent afterward;
- activity reads never address negative/non-existent synthetic indices when the fixture has fewer than 100 records;
- retention deletion removes only the intended oldest prefix and preserves the first retained event.

## Build metadata

Dart/FRB evidence records Dart and native-library build modes separately. Rust-native evidence records its Rust build mode using `cfg!(debug_assertions)`. Comparisons should only be treated as meaningful when build modes and runner settings are compatible.

## Output

Dart/FRB emits `DXTR_BOX_REAL_WORLD ...` JSONL lines. Rust-native emits `DXTR_BOX_REAL_WORLD_RUST ...` JSONL lines. PR4 will wire these into CI artifacts and close the 0.10 milestone.
