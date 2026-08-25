# MessagePack Decoder Evaluation Decision

Status: **retain `msgpack_dart 1.0.1` in production**.

This decision records the evidence collected after the 1.1 release-readiness work. It does not change the public API, native profiles, query semantics, package SDK minimums, or durable `dxtr_box/1` format.

## Compatibility gate

`test/codec_compatibility_corpus_test.dart` pins exact current MessagePack bytes for primitives and every existing `@dxtr:*` tagged value, including integer and string/binary/array width boundaries. The isolated decoder diagnostic consumes those exact bytes before timing a candidate implementation.

The candidate used for this evaluation was `pro_mpack 3.2.0`. It remains isolated under `tool/decoder_benchmark` because it requires Dart `^3.10.0`, while the package contract remains Dart `>=3.4.0 <4.0.0`.

## Same-run decoder results

Read-path Benchmark run 230 on Linux x64, Flutter 3.47.1 / Dart 3.13.1:

| payload | bytes | msgpack_dart ns/op | pro_mpack ns/op | result |
| --- | ---: | ---: | ---: | --- |
| `flat_map_16` | 180 | 8,223 | 2,126 | candidate faster |
| `flat_map_64` | 708 | 5,380 | 6,677 | current faster |
| `list_256` | 399 | 4,439 | 2,140 | candidate faster |
| `bytes_4096` | 4,112 | 104 | 344 | current faster |
| `nested` | 1,752 | 12,818 | 15,790 | current faster |

The candidate is materially faster for some smaller/container-heavy shapes but slower for larger maps, nested structures, and binary-heavy payloads. There is no consistent workload-wide advantage.

## Decision

Do not replace `msgpack_dart 1.0.1` now.

Reasons:

1. Performance is mixed rather than a clear, representative win.
2. `pro_mpack 3.2.0` would raise the effective Dart requirement to 3.10 if adopted directly, conflicting with the supported Dart >=3.4 contract.
3. The current codec already has byte-level compatibility evidence and no demonstrated wire-layout bottleneck requiring a storage-format migration.
4. A codec replacement would create compatibility and maintenance risk without enough measured end-to-end benefit.

## Revisit criteria

Reopen decoder replacement only when at least one of these becomes true:

- a candidate supports the package's minimum Dart SDK without raising it;
- representative same-run workloads show a consistent and material improvement, not isolated microbenchmark wins;
- end-to-end `Box.getAll` / query evidence shows decoder time is the dominant remaining production cost and the candidate reduces that full-path cost;
- the existing decoder has a correctness, security, maintenance, or ecosystem problem that justifies migration risk.

Any future replacement must still pass the exact `dxtr_box/1` compatibility corpus before production adoption. If encoded bytes change, treat that as a storage-format/version migration decision rather than an implementation detail.
