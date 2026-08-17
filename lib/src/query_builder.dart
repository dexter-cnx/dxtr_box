import 'box.dart';
import 'query.dart';

/// Starts a fluent query without changing the underlying [BoxQuery] model.
///
/// The builder is a Dart-side AST authoring helper only. Calling [build]
/// produces the same declarative query objects accepted by [Box.query].
final class BoxQueryBuilder {
  const BoxQueryBuilder._(this._root);

  /// Starts a fluent query at [field].
  static QueryFieldBuilder where(String field) {
    return QueryFieldBuilder._first(field);
  }

  final QueryFilter _root;

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

  /// Compiles the fluent expression to the existing declarative query AST.
  BoxQuery build() => BoxQuery(where: _root);

  BoxQueryBuilder _append(
    QueryLogicalOperator operator,
    QueryFilter filter,
  ) {
    final root = switch (operator) {
      QueryLogicalOperator.and => QueryGroup.and(<QueryFilter>[_root, filter]),
      QueryLogicalOperator.or => QueryGroup.or(<QueryFilter>[_root, filter]),
    };
    return BoxQueryBuilder._(root);
  }

  static QueryFilter _buildExplicitGroup(
    BoxQueryBuilder Function(QueryGroupStart group) buildGroup,
  ) {
    final grouped = buildGroup(const QueryGroupStart());
    return grouped._root;
  }
}

/// Entry point supplied to [BoxQueryBuilder.andGroup] and
/// [BoxQueryBuilder.orGroup].
final class QueryGroupStart {
  const QueryGroupStart();

  QueryFieldBuilder where(String field) => BoxQueryBuilder.where(field);
}

/// Field stage of the fluent query builder.
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

/// Convenience entry point for the fluent authoring surface.
///
/// Execution remains [Box.query] in 0.7 PR1; PR2 adds terminal query
/// ergonomics without introducing a second query engine.
extension BoxFluentQuery on Box {
  QueryFieldBuilder where(String field) => BoxQueryBuilder.where(field);
}
