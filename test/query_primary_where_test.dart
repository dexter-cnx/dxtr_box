import 'package:dxtr_box/dxtr_box.dart';
import 'package:dxtr_box/src/native_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('primary Fluent Box Query where API', () {
    test('chains document-style comparisons as AND predicates', () {
      final box = _box();
      final query = box
          .queryBuilder()
          .where('status', isEqualTo: 'active')
          .where('profile.age', isGreaterThanOrEqualTo: 18)
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      expect(root.filters, hasLength(2));

      final status = root.filters[0] as QueryComparison;
      expect(status.field, 'status');
      expect(status.operator, QueryOperator.equal);
      expect(status.value, 'active');

      final age = root.filters[1] as QueryComparison;
      expect(age.field, 'profile.age');
      expect(age.operator, QueryOperator.greaterThanOrEqual);
      expect(age.value, 18);
    });

    test('supports null as an explicit equality value', () {
      final query = _box()
          .queryBuilder()
          .where('deletedAt', isEqualTo: null)
          .build();

      final comparison = query.where as QueryComparison;
      expect(comparison.operator, QueryOperator.equal);
      expect(comparison.value, isNull);
    });

    test('whereIn desugars to an OR equality group', () {
      final query = _box()
          .queryBuilder()
          .where(
            'status',
            whereIn: const <Object?>['active', 'pending'],
          )
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.or);
      expect(root.filters, hasLength(2));
      for (final filter in root.filters) {
        final comparison = filter as QueryComparison;
        expect(comparison.field, 'status');
        expect(comparison.operator, QueryOperator.equal);
      }
    });

    test('chained whereIn stays grouped under the outer AND', () {
      final query = _box()
          .queryBuilder()
          .where('active', isEqualTo: true)
          .where(
            'role',
            whereIn: const <Object?>['admin', 'editor'],
          )
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      expect(root.filters, hasLength(2));
      final setGroup = root.filters.last as QueryGroup;
      expect(setGroup.operator, QueryLogicalOperator.or);
      expect(setGroup.filters, hasLength(2));
    });

    test('whereNotIn desugars to an AND inequality group', () {
      final query = _box()
          .queryBuilder()
          .where(
            'status',
            whereNotIn: const <Object?>['deleted', 'blocked'],
          )
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      expect(root.filters, hasLength(2));
      for (final filter in root.filters) {
        expect(
          (filter as QueryComparison).operator,
          QueryOperator.notEqual,
        );
      }
    });

    test('requires exactly one operator and non-empty set operands', () {
      final start = _box().queryBuilder();

      expect(() => start.where('status'), throwsArgumentError);
      expect(
        () => start.where(
          'status',
          isEqualTo: 'active',
          isNotEqualTo: 'deleted',
        ),
        throwsArgumentError,
      );
      expect(
        () => start.where('status', whereIn: const <Object?>[]),
        throwsArgumentError,
      );
      expect(
        () => start.where('status', whereNotIn: const <Object?>[]),
        throwsArgumentError,
      );
    });

    test('retains canonical nested-field validation', () {
      expect(
        () => _box()
            .queryBuilder()
            .where('profile..age', isGreaterThan: 18),
        throwsArgumentError,
      );
    });
  });
}

Box _box() {
  return Box.internal(
    name: 'query-primary-test',
    watcherId: 'query-primary-watcher',
    api: _NoopNativeBoxApi(),
    metadata: BoxMetadata(),
    onClose: () {},
  );
}

final class _NoopNativeBoxApi implements NativeBoxApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
