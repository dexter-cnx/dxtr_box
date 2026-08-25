# Query Public Overhead Decomposition

This diagnostic isolates the remaining Dart-side overhead around native query execution without changing production behavior.

The benchmark records same-run medians for:

- query wire construction only;
- MessagePack encoding of a prebuilt query wire;
- query wire construction plus encoding;
- native adapter query execution with a pre-encoded payload;
- native adapter query execution with per-call wire construction and encoding;
- the complete public `Box.query` path.

The benchmark intentionally mirrors the current query wire shape used by `Box.query`. Same-run adjacent ratios are the primary evidence. Absolute hosted-run timings are diagnostic only.

The next production optimization should be selected only after this decomposition shows whether query-wire construction/encoding or another public-layer cost is material. The diagnostic does not change the public API, query semantics, native profiles, or the `dxtr_box/1` storage format.
