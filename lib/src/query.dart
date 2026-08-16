/// Declarative query contract for the 0.3 query/index milestone.
///
/// Query and index semantics are intentionally independent of the execution
/// engine so native scans and persisted indexes can evolve without changing
/// the Dart-facing model.
sealed class QueryFilter {
  const QueryFilter();
}

final class QueryComparison extends QueryFilter {
  QueryComparison({
    required this.field,
    required this.operator,
    this.value,
    this.upperValue,
  }) {
    _validateField(field);
    if (operator == QueryOperator.between && upperValue == null) {
      throw ArgumentError.value(
        upperValue,
        'upperValue',
        'between requires an upper value',
      );
    }
  }

  final String field;
  final QueryOperator operator;
  final dynamic value;
  final dynamic upperValue;
}

enum QueryOperator {
  equal,
  notEqual,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  between,
  isNull,
  isNotNull,
}

enum QueryLogicalOperator { and, or }

enum QuerySortDirection { ascending, descending }

enum QueryNullOrder { first, last }

final class QuerySort {
  QuerySort({
    required this.field,
    this.direction = QuerySortDirection.ascending,
    this.nulls = QueryNullOrder.last,
  }) {
    _validateField(field);
  }

  final String field;
  final QuerySortDirection direction;
  final QueryNullOrder nulls;
}

final class QueryGroup extends QueryFilter {
  QueryGroup.and(Iterable<QueryFilter> filters)
    : this._(QueryLogicalOperator.and, filters);

  QueryGroup.or(Iterable<QueryFilter> filters)
    : this._(QueryLogicalOperator.or, filters);

  QueryGroup._(this.operator, Iterable<QueryFilter> filters)
    : filters = List<QueryFilter>.unmodifiable(filters) {
    if (this.filters.isEmpty) {
      throw ArgumentError.value(
        filters,
        'filters',
        '${operator.name.toUpperCase()} requires at least one filter',
      );
    }
  }

  final QueryLogicalOperator operator;
  final List<QueryFilter> filters;
}

final class BoxQuery {
  BoxQuery({
    required this.where,
    Iterable<QuerySort> sortBy = const <QuerySort>[],
    this.limit,
    this.offset = 0,
  }) : sortBy = List<QuerySort>.unmodifiable(sortBy) {
    if (limit != null && limit! <= 0) {
      throw ArgumentError.value(limit, 'limit', 'limit must be greater than 0');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'offset cannot be negative');
    }
  }

  final QueryFilter where;
  final List<QuerySort> sortBy;
  final int? limit;
  final int offset;
}

/// Persisted secondary-index declaration.
///
/// 0.3 starts with one scalar value index per field path. Composite, text,
/// multi-value, and unique-index semantics remain separate future extensions.
final class IndexDefinition {
  IndexDefinition({required this.name, required this.field}) {
    _validateIdentifier(name, 'name');
    _validateField(field);
  }

  final String name;
  final String field;
}

void _validateField(String field) {
  if (field.isEmpty ||
      field.startsWith('.') ||
      field.endsWith('.') ||
      field.split('.').any((segment) => segment.isEmpty)) {
    throw ArgumentError.value(
      field,
      'field',
      'field must be a non-empty dotted path',
    );
  }
}

void _validateIdentifier(String value, String name) {
  final valid = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
  if (!valid.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must start with a letter and contain only letters, digits, _ or -',
    );
  }
}
