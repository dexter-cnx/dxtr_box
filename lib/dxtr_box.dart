/// Rust-backed ACID box storage for Flutter.
///
/// The public API exposes asynchronous box ergonomics, native encryption,
/// watch streams, declarative queries, persisted secondary indexes, and Hive CE
/// migration helpers without model code generation.
library;

export 'src/box.dart';
export 'src/box_event.dart';
export 'src/dxtr_box.dart' show BoxStore, DxtrBox;
export 'src/hive_ce_migration.dart';
export 'src/query.dart';
export 'src/query_builder.dart';
export 'src/query_field.dart';
export 'src/query_start.dart';
