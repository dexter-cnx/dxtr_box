import 'box.dart';
import 'query_builder.dart';

/// Compatibility-safe entry point for the 1.3 Fluent Box Query surface.
///
/// [Box.query] already executes a declarative [BoxQuery], so 1.3 uses
/// [BoxQueryStart] through [BoxPrimaryFluentQuery.queryBuilder] instead of
/// overloading `query()` with a zero-argument builder form.
final class BoxQueryStart {
  const BoxQueryStart._(this._box);

  final Box _box;

  /// Starts a box-bound fluent query at [field].
  BoundQueryFieldBuilder where(String field) => _box.queryWhere(field);
}

/// Primary fluent query authoring surface for [Box].
extension BoxPrimaryFluentQuery on Box {
  /// Starts an immutable Fluent Box Query while preserving `query(BoxQuery)`.
  BoxQueryStart queryBuilder() => BoxQueryStart._(this);
}
