# FRB read-boundary matrix

This diagnostic isolates read-path cost across the authoritative storage core and Flutter boundary layers without changing production semantics.

Measured layers:

1. `rust_core` — direct Rust core `get_all` / query execution.
2. `generated_frb` — generated flutter_rust_bridge API calls.
3. `native_adapter` — `FrbNativeBoxApi` mapping/copy layer.
4. `public_dart` — public `Box.getAll` / `Box.query`, including Dart codec work.

The matrix uses the same 100-record logical dataset for batch sizes 10 and 100 and for an equality query limited to 10 results. Hosted-runner absolute latency is diagnostic only; same-run ratios between adjacent layers are the primary evidence.

No production optimization should be merged from this investigation unless the matrix identifies a repeatable boundary cost and the proposed change preserves the public Future API, durable `dxtr_box/1` storage semantics, ordering, missing-key behavior, query semantics, and error delivery.
