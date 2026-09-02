import 'box.dart';
import 'query_builder.dart';

const _queryUnset = Object();

/// Compatibility-safe entry point for the 1.3 Fluent Box Query surface.
///
/// [Box.query] already executes a declarative [BoxQuery], so 1.3 uses
/// [BoxQueryStart] through [BoxPrimaryFluentQuery.queryBuilder] instead of
/// overloading `query()` with a zero-argument builder form.
final class BoxQueryStart {
  const BoxQueryStart._(this._box);

  final Box _box;

  /// Starts a box-bound fluent query using exactly one comparison mode.
  ///
  /// Set operators intentionally compile to existing boolean/comparison AST
  /// nodes so they preserve the established Rust wire format and execution
  /// semantics.
  BoundBoxQueryBuilder where(
    String field, {
    Object? isEqualTo = _queryUnset,
    Object? isNotEqualTo = _queryUnset,
    Object? isLessThan = _queryUnset,
    Object? isLessThanOrEqualTo = _queryUnset,
    Object? isGreaterThan = _queryUnset,
    Object? isGreaterThanOrEqualTo = _queryUnset,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
  }) {
    return _startWhere(
      _box,
      field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
    );
  }
}

/// Primary fluent query authoring surface for [Box].
extension BoxPrimaryFluentQuery on Box {
  /// Starts an immutable Fluent Box Query while preserving `query(BoxQuery)`.
  BoxQueryStart queryBuilder() => BoxQueryStart._(this);
}

/// Adds the primary document-style `where(...)` syntax to an existing query.
extension BoundBoxPrimaryWhere on BoundBoxQueryBuilder {
  /// Appends an AND predicate using exactly one comparison mode.
  BoundBoxQueryBuilder where(
    String field, {
    Object? isEqualTo = _queryUnset,
    Object? isNotEqualTo = _queryUnset,
    Object? isLessThan = _queryUnset,
    Object? isLessThanOrEqualTo = _queryUnset,
    Object? isGreaterThan = _queryUnset,
    Object? isGreaterThanOrEqualTo = _queryUnset,
    Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn,
  }) {
    return _appendWhere(
      this,
      field,
      isEqualTo: isEqualTo,
      isNotEqualTo: isNotEqualTo,
      isLessThan: isLessThan,
      isLessThanOrEqualTo: isLessThanOrEqualTo,
      isGreaterThan: isGreaterThan,
      isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
      whereIn: whereIn,
      whereNotIn: whereNotIn,
    );
  }
}

BoundBoxQueryBuilder _startWhere(
  Box box,
  String field, {
  required Object? isEqualTo,
  required Object? isNotEqualTo,
  required Object? isLessThan,
  required Object? isLessThanOrEqualTo,
  required Object? isGreaterThan,
  required Object? isGreaterThanOrEqualTo,
  required Iterable<Object?>? whereIn,
  required Iterable<Object?>? whereNotIn,
}) {
  _validateSingleMode(
    isEqualTo: isEqualTo,
    isNotEqualTo: isNotEqualTo,
    isLessThan: isLessThan,
    isLessThanOrEqualTo: isLessThanOrEqualTo,
    isGreaterThan: isGreaterThan,
    isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
    whereIn: whereIn,
    whereNotIn: whereNotIn,
  );

  final fieldBuilder = box.queryWhere(field);
  if (!identical(isEqualTo, _queryUnset)) {
    return fieldBuilder.equals(isEqualTo);
  }
  if (!identical(isNotEqualTo, _queryUnset)) {
    return fieldBuilder.notEquals(isNotEqualTo);
  }
  if (!identical(isLessThan, _queryUnset)) {
    return fieldBuilder.lt(isLessThan);
  }
  if (!identical(isLessThanOrEqualTo, _queryUnset)) {
    return fieldBuilder.lte(isLessThanOrEqualTo);
  }
  if (!identical(isGreaterThan, _queryUnset)) {
    return fieldBuilder.gt(isGreaterThan);
  }
  if (!identical(isGreaterThanOrEqualTo, _queryUnset)) {
    return fieldBuilder.gte(isGreaterThanOrEqualTo);
  }
  if (whereIn != null) {
    final values = _validatedSetValues(whereIn, 'whereIn');
    var builder = fieldBuilder.equals(values.first);
    for (final value in values.skip(1)) {
      builder = builder.or(field).equals(value);
    }
    return builder;
  }

  final values = _validatedSetValues(whereNotIn!, 'whereNotIn');
  var builder = fieldBuilder.notEquals(values.first);
  for (final value in values.skip(1)) {
    builder = builder.and(field).notEquals(value);
  }
  return builder;
}

BoundBoxQueryBuilder _appendWhere(
  BoundBoxQueryBuilder base,
  String field, {
  required Object? isEqualTo,
  required Object? isNotEqualTo,
  required Object? isLessThan,
  required Object? isLessThanOrEqualTo,
  required Object? isGreaterThan,
  required Object? isGreaterThanOrEqualTo,
  required Iterable<Object?>? whereIn,
  required Iterable<Object?>? whereNotIn,
}) {
  _validateSingleMode(
    isEqualTo: isEqualTo,
    isNotEqualTo: isNotEqualTo,
    isLessThan: isLessThan,
    isLessThanOrEqualTo: isLessThanOrEqualTo,
    isGreaterThan: isGreaterThan,
    isGreaterThanOrEqualTo: isGreaterThanOrEqualTo,
    whereIn: whereIn,
    whereNotIn: whereNotIn,
  );

  if (!identical(isEqualTo, _queryUnset)) {
    return base.and(field).equals(isEqualTo);
  }
  if (!identical(isNotEqualTo, _queryUnset)) {
    return base.and(field).notEquals(isNotEqualTo);
  }
  if (!identical(isLessThan, _queryUnset)) {
    return base.and(field).lt(isLessThan);
  }
  if (!identical(isLessThanOrEqualTo, _queryUnset)) {
    return base.and(field).lte(isLessThanOrEqualTo);
  }
  if (!identical(isGreaterThan, _queryUnset)) {
    return base.and(field).gt(isGreaterThan);
  }
  if (!identical(isGreaterThanOrEqualTo, _queryUnset)) {
    return base.and(field).gte(isGreaterThanOrEqualTo);
  }
  if (whereIn != null) {
    final values = _validatedSetValues(whereIn, 'whereIn');
    return base.andGroup((group) {
      var nested = group.where(field).equals(values.first);
      for (final value in values.skip(1)) {
        nested = nested.or(field).equals(value);
      }
      return nested;
    });
  }

  final values = _validatedSetValues(whereNotIn!, 'whereNotIn');
  return base.andGroup((group) {
    var nested = group.where(field).notEquals(values.first);
    for (final value in values.skip(1)) {
      nested = nested.and(field).notEquals(value);
    }
    return nested;
  });
}

void _validateSingleMode({
  required Object? isEqualTo,
  required Object? isNotEqualTo,
  required Object? isLessThan,
  required Object? isLessThanOrEqualTo,
  required Object? isGreaterThan,
  required Object? isGreaterThanOrEqualTo,
  required Iterable<Object?>? whereIn,
  required Iterable<Object?>? whereNotIn,
}) {
  final count = <bool>[
    !identical(isEqualTo, _queryUnset),
    !identical(isNotEqualTo, _queryUnset),
    !identical(isLessThan, _queryUnset),
    !identical(isLessThanOrEqualTo, _queryUnset),
    !identical(isGreaterThan, _queryUnset),
    !identical(isGreaterThanOrEqualTo, _queryUnset),
    whereIn != null,
    whereNotIn != null,
  ].where((selected) => selected).length;

  if (count != 1) {
    throw ArgumentError(
      'where() requires exactly one comparison or set operator.',
    );
  }
}

List<Object?> _validatedSetValues(Iterable<Object?> values, String name) {
  final snapshot = List<Object?>.unmodifiable(values);
  if (snapshot.isEmpty) {
    throw ArgumentError.value(
      values,
      name,
      '$name requires at least one value',
    );
  }
  return snapshot;
}
