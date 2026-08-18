import 'box.dart';
import 'query.dart';

/// Starts a fluent query without changing the underlying [BoxQuery] model.
///
/// The builder is a Dart-side AST authoring helper only. Calling [build]
/// produces the same declarative query objects accepted by [Box.query].
final class BoxQueryBuilder {
  const BoxQueryBuilder._(
    this._root, {
    List<QuerySort> sortBy = const <QuerySort>[],
    int? limit,
    int offset = 0,
  })  : _sortBy = sortBy,
        _limit = limit,
        _offset = offset;

  /// Starts a fluent query at [field].
  static QueryFieldBuilder where(String field) {
    return QueryFieldBuilder._first(field);
  }

  final QueryFilter _root;
  final List<QuerySort> _sortBy;
  final int? _limit;
  final int _offset;

  /// Adds an AND comparison for [field].
  QueryFieldBuilder and(String field) {
    return QueryFieldBuilder._next(this, QueryLogicalOperator.and, field);
  }

  /// Adds an OR comparison for [field].
  QueryFieldBuilder or(String field) {
    return QueryFieldBuilder._next(this, QueryLogicalOperator.or, field);
  }

  /// Adds an explicitly grouped AND expression.
  ///
  /// Mixed AND/OR chains are left-associative. Use this method when explicit
  /// grouping is required.
  BoxQueryBuilder andGroup(
    BoxQueryBuilder Function(QueryGroupStart group) buildGroup,
  ) {
    return _append(
      QueryLogicalOperator.and,
      _buildExplicitGroup(buildGroup),
    );
  }

  /// Adds an explicitly grouped OR expression.
  ///
  /// Mixed AND/OR chains are left-associative. Use this method when explicit
  /// grouping is required.
  BoxQueryBuilder orGroup(
    BoxQueryBuilder Function(QueryGroupStart group) buildGroup,
  ) {
    return _append(
      QueryLogicalOperator.or,
      _buildExplicitGroup(buildGroup),
    );
  }

  /// Adds a deterministic semantic sort to the existing query AST.
  BoxQueryBuilder orderBy(
    String field, {
    bool descending = false,
    QueryNullOrder nulls = QueryNullOrder.last,
  }) {
    return BoxQueryBuilder._(
      _root,
      sortBy: <QuerySort>[
        ..._sortBy,
        QuerySort(
          field: field,
          direction: descending
              ? QuerySortDirection.descending
              : QuerySortDirection.ascending,
          nulls: nulls,
        ),
      ],
      limit: _limit,
      offset: _offset,
    );
  }

  /// Applies the existing native query offset semantics.
  BoxQueryBuilder offset(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'offset cannot be negative');
    }
    return BoxQueryBuilder._(
      _root,
      sortBy: _sortBy,
      limit: _limit,
      offset: value,
    );
  }

  /// Applies the existing native query limit semantics.
  BoxQueryBuilder limit(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'value', 'limit must be greater than 0');
    }
    return BoxQueryBuilder._(
      _root,
      sortBy: _sortBy,
      limit: value,
      offset: _offset,
    );
  }

  /// Compiles the fluent expression to the existing declarative query AST.
  BoxQuery build() {
    return BoxQuery(
      where: _root,
      sortBy: _sortBy,
      limit: _limit,
      offset: _offset,
    );
  }

  BoxQueryBuilder _append(
    QueryLogicalOperator operator,
    QueryFilter filter,
  ) {
    final root = switch (operator) {
      QueryLogicalOperator.and => QueryGroup.and(<QueryFilter>[_root, filter]),
      QueryLogicalOperator.or => QueryGroup.or(<QueryFilter>[_root, filter]),
    };
    return BoxQueryBuilder._(
      root,
      sortBy: _sortBy,
      limit: _limit,
      offset: _offset,
    );
  }

  static QueryFilter _buildExplicitGroup(
    BoxQueryBuilder Function(QueryGroupStart group) buildGroup,
  ) {
    final grouped = buildGroup(const QueryGroupStart());
    return grouped._root;
  }
}

/// A fluent query builder that is bound to the originating [Box].
///
/// Only this bound path exposes [find]. Standalone [BoxQueryBuilder] instances
/// remain pure AST builders and therefore cannot fail later due to a missing
/// execution context.
final class BoundBoxQueryBuilder {
  const BoundBoxQueryBuilder._(this._box, this._builder);

  final Box _box;
  final BoxQueryBuilder _builder;

  BoundQueryFieldBuilder and(String field) {
    return BoundQueryFieldBuilder._(_box, _builder.and(field));
  }

  BoundQueryFieldBuilder or(String field) {
    return BoundQueryFieldBuilder._(_box, _builder.or(field));
  }

  BoundBoxQueryBuilder andGroup(
    BoxQueryBuilder Function(QueryGroupStart group) buildGroup,
  ) {
    return BoundBoxQueryBuilder._(_box, _builder.andGroup(buildGroup));
  }

  BoundBoxQueryBuilder orGroup(
    BoxQueryBuilder Function(QueryGroupStart group) buildGroup,
  ) {
    return BoundBoxQueryBuilder._(_box, _builder.orGroup(buildGroup));
  }

  BoundBoxQueryBuilder orderBy(
    String field, {
    bool descending = false,
    QueryNullOrder nulls = QueryNullOrder.last,
  }) {
    return BoundBoxQueryBuilder._(
      _box,
      _builder.orderBy(field, descending: descending, nulls: nulls),
    );
  }

  BoundBoxQueryBuilder offset(int value) {
    return BoundBoxQueryBuilder._(_box, _builder.offset(value));
  }

  BoundBoxQueryBuilder limit(int value) {
    return BoundBoxQueryBuilder._(_box, _builder.limit(value));
  }

  BoxQuery build() => _builder.build();

  /// Executes the built query through the existing one-crossing [Box.query]
  /// path.
  Future<List<MapEntry<String, dynamic>>> find() => _box.query(build());
}

/// Entry point supplied to [BoxQueryBuilder.andGroup] and
/// [BoxQueryBuilder.orGroup].
final class QueryGroupStart {
  const QueryGroupStart();

  QueryFieldBuilder where(String field) => BoxQueryBuilder.where(field);
}

/// Field stage of the standalone fluent query builder.
///
/// A comparison must be selected before another logical clause can be added.
final class QueryFieldBuilder {
  QueryFieldBuilder._first(this.field)
      : _base = null,
        _logicalOperator = null;

  QueryFieldBuilder._next(
    this._base,
    this._logicalOperator,
    this.field,
  );

  final BoxQueryBuilder? _base;
  final QueryLogicalOperator? _logicalOperator;
  final String field;

  BoxQueryBuilder equals(dynamic value) => _comparison(
        QueryOperator.equal,
        value: value,
      );

  BoxQueryBuilder notEquals(dynamic value) => _comparison(
        QueryOperator.notEqual,
        value: value,
      );

  BoxQueryBuilder gt(dynamic value) => _comparison(
        QueryOperator.greaterThan,
        value: value,
      );

  BoxQueryBuilder gte(dynamic value) => _comparison(
        QueryOperator.greaterThanOrEqual,
        value: value,
      );

  BoxQueryBuilder lt(dynamic value) => _comparison(
        QueryOperator.lessThan,
        value: value,
      );

  BoxQueryBuilder lte(dynamic value) => _comparison(
        QueryOperator.lessThanOrEqual,
        value: value,
      );

  BoxQueryBuilder between(dynamic lowerValue, dynamic upperValue) =>
      _comparison(
        QueryOperator.between,
        value: lowerValue,
        upperValue: upperValue,
      );

  BoxQueryBuilder isNull() => _comparison(QueryOperator.isNull);

  BoxQueryBuilder isNotNull() => _comparison(QueryOperator.isNotNull);

  BoxQueryBuilder _comparison(
    QueryOperator operator, {
    dynamic value,
    dynamic upperValue,
  }) {
    final comparison = QueryComparison(
      field: field,
      operator: operator,
      value: value,
      upperValue: upperValue,
    );
    final base = _base;
    if (base == null) {
      return BoxQueryBuilder._(comparison);
    }
    return base._append(_logicalOperator!, comparison);
  }
}

/// Field stage for a query that retains its originating [Box].
final class BoundQueryFieldBuilder {
  const BoundQueryFieldBuilder._(this._box, this._fieldBuilder);

  final Box _box;
  final QueryFieldBuilder _fieldBuilder;

  BoundBoxQueryBuilder equals(dynamic value) {
    return _bound(_fieldBuilder.equals(value));
  }

  BoundBoxQueryBuilder notEquals(dynamic value) {
    return _bound(_fieldBuilder.notEquals(value));
  }

  BoundBoxQueryBuilder gt(dynamic value) {
    return _bound(_fieldBuilder.gt(value));
  }

  BoundBoxQueryBuilder gte(dynamic value) {
    return _bound(_fieldBuilder.gte(value));
  }

  BoundBoxQueryBuilder lt(dynamic value) {
    return _bound(_fieldBuilder.lt(value));
  }

  BoundBoxQueryBuilder lte(dynamic value) {
    return _bound(_fieldBuilder.lte(value));
  }

  BoundBoxQueryBuilder between(dynamic lowerValue, dynamic upperValue) {
    return _bound(_fieldBuilder.between(lowerValue, upperValue));
  }

  BoundBoxQueryBuilder isNull() => _bound(_fieldBuilder.isNull());

  BoundBoxQueryBuilder isNotNull() => _bound(_fieldBuilder.isNotNull());

  BoundBoxQueryBuilder _bound(BoxQueryBuilder builder) {
    return BoundBoxQueryBuilder._(_box, builder);
  }
}

/// Convenience entry point for the fluent authoring and execution surface.
///
/// `Box.where` is already a legacy Dart predicate-scan API, so the fluent
/// query entry point uses the collision-free [queryWhere] name.
extension BoxFluentQuery on Box {
  BoundQueryFieldBuilder queryWhere(String field) {
    return BoundQueryFieldBuilder._(this, BoxQueryBuilder.where(field));
  }
}
