/// Declarative query contract for the 0.3 query/index milestone.
///
/// This file intentionally defines query and index semantics independently of
/// the execution engine. Native execution and persisted indexes can evolve
/// without changing the Dart-facing query model.
sealed class DxtrCondition {
  const DxtrCondition();
}

final class DxtrCompare extends DxtrCondition {
  DxtrCompare({
    required this.field,
    required this.operator,
    this.value,
    this.upperValue,
  }) {
    _validateField(field);
    if (operator == DxtrCompareOperator.between && upperValue == null) {
      throw ArgumentError.value(
        upperValue,
        'upperValue',
        'between requires an upper value',
      );
    }
  }

  final String field;
  final DxtrCompareOperator operator;
  final dynamic value;
  final dynamic upperValue;
}

enum DxtrCompareOperator {
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

final class DxtrAnd extends DxtrCondition {
  DxtrAnd(Iterable<DxtrCondition> conditions)
      : conditions = List<DxtrCondition>.unmodifiable(conditions) {
    if (this.conditions.isEmpty) {
      throw ArgumentError.value(
        conditions,
        'conditions',
        'AND requires at least one condition',
      );
    }
  }

  final List<DxtrCondition> conditions;
}

final class DxtrOr extends DxtrCondition {
  DxtrOr(Iterable<DxtrCondition> conditions)
      : conditions = List<DxtrCondition>.unmodifiable(conditions) {
    if (this.conditions.isEmpty) {
      throw ArgumentError.value(
        conditions,
        'conditions',
        'OR requires at least one condition',
      );
    }
  }

  final List<DxtrCondition> conditions;
}

final class DxtrQuery {
  DxtrQuery({
    required this.where,
    this.limit,
    this.offset = 0,
  }) {
    if (limit != null && limit! <= 0) {
      throw ArgumentError.value(limit, 'limit', 'limit must be greater than 0');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'offset cannot be negative');
    }
  }

  final DxtrCondition where;
  final int? limit;
  final int offset;
}

/// Persisted secondary-index declaration.
///
/// 0.3 starts with one scalar value index per field path. Composite, text,
/// multi-value, and unique-index semantics remain separate future extensions.
final class DxtrIndexDefinition {
  DxtrIndexDefinition({
    required this.name,
    required this.field,
  }) {
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
