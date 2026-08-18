import 'box.dart';
import 'query.dart';
import 'query_builder.dart';

/// Optional typed metadata for a query field path.
///
/// [DxtrField] does not define a schema and does not require code generation.
/// It only carries a reusable Dart type plus the same string path consumed by
/// the existing query AST.
final class DxtrField<T> {
  const DxtrField(this.path);

  /// Existing dotted-path field name used by [QueryComparison] and [QuerySort].
  final String path;

  /// Starts a standalone typed fluent query at this field.
  TypedQueryFieldBuilder<T> where() {
    return TypedQueryFieldBuilder<T>._(BoxQueryBuilder.where(path));
  }

  @override
  String toString() => 'DxtrField<$T>($path)';
}

/// Typed field stage for standalone query composition.
///
/// Values are checked by Dart at authoring time, then delegated unchanged to
/// the existing [QueryFieldBuilder] and therefore compile to the same AST.
final class TypedQueryFieldBuilder<T> {
  const TypedQueryFieldBuilder._(this._delegate);

  final QueryFieldBuilder _delegate;

  BoxQueryBuilder equals(T value) => _delegate.equals(value);

  BoxQueryBuilder notEquals(T value) => _delegate.notEquals(value);

  BoxQueryBuilder gt(T value) => _delegate.gt(value);

  BoxQueryBuilder gte(T value) => _delegate.gte(value);

  BoxQueryBuilder lt(T value) => _delegate.lt(value);

  BoxQueryBuilder lte(T value) => _delegate.lte(value);

  BoxQueryBuilder between(T lowerValue, T upperValue) {
    return _delegate.between(lowerValue, upperValue);
  }

  BoxQueryBuilder isNull() => _delegate.isNull();

  BoxQueryBuilder isNotNull() => _delegate.isNotNull();
}

/// Typed field stage for a query bound to an originating [Box].
final class BoundTypedQueryFieldBuilder<T> {
  const BoundTypedQueryFieldBuilder._(this._delegate);

  final BoundQueryFieldBuilder _delegate;

  BoundBoxQueryBuilder equals(T value) => _delegate.equals(value);

  BoundBoxQueryBuilder notEquals(T value) => _delegate.notEquals(value);

  BoundBoxQueryBuilder gt(T value) => _delegate.gt(value);

  BoundBoxQueryBuilder gte(T value) => _delegate.gte(value);

  BoundBoxQueryBuilder lt(T value) => _delegate.lt(value);

  BoundBoxQueryBuilder lte(T value) => _delegate.lte(value);

  BoundBoxQueryBuilder between(T lowerValue, T upperValue) {
    return _delegate.between(lowerValue, upperValue);
  }

  BoundBoxQueryBuilder isNull() => _delegate.isNull();

  BoundBoxQueryBuilder isNotNull() => _delegate.isNotNull();
}

/// Typed-field helpers for standalone fluent query continuation.
extension BoxQueryBuilderTypedFields on BoxQueryBuilder {
  TypedQueryFieldBuilder<T> andField<T>(DxtrField<T> field) {
    return TypedQueryFieldBuilder<T>._(and(field.path));
  }

  TypedQueryFieldBuilder<T> orField<T>(DxtrField<T> field) {
    return TypedQueryFieldBuilder<T>._(or(field.path));
  }

  BoxQueryBuilder orderByField<T>(
    DxtrField<T> field, {
    bool descending = false,
    QueryNullOrder nulls = QueryNullOrder.last,
  }) {
    return orderBy(field.path, descending: descending, nulls: nulls);
  }
}

/// Typed-field helpers for box-bound fluent query continuation.
extension BoundBoxQueryBuilderTypedFields on BoundBoxQueryBuilder {
  BoundTypedQueryFieldBuilder<T> andField<T>(DxtrField<T> field) {
    return BoundTypedQueryFieldBuilder<T>._(and(field.path));
  }

  BoundTypedQueryFieldBuilder<T> orField<T>(DxtrField<T> field) {
    return BoundTypedQueryFieldBuilder<T>._(or(field.path));
  }

  BoundBoxQueryBuilder orderByField<T>(
    DxtrField<T> field, {
    bool descending = false,
    QueryNullOrder nulls = QueryNullOrder.last,
  }) {
    return orderBy(field.path, descending: descending, nulls: nulls);
  }
}

/// Typed-field helpers for explicit predicate groups.
extension QueryGroupStartTypedFields on QueryGroupStart {
  TypedQueryFieldBuilder<T> whereField<T>(DxtrField<T> field) {
    return TypedQueryFieldBuilder<T>._(where(field.path));
  }
}

/// Optional typed entry point for queries bound to a [Box].
extension BoxTypedFieldQuery on Box {
  BoundTypedQueryFieldBuilder<T> queryWhereField<T>(DxtrField<T> field) {
    return BoundTypedQueryFieldBuilder<T>._(queryWhere(field.path));
  }
}
