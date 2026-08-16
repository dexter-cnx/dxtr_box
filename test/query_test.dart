import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('query contract', () {
    test('supports nested field comparisons and pagination', () {
      final query = BoxQuery(
        where: QueryGroup.and(<QueryFilter>[
          QueryComparison(
            field: 'profile.age',
            operator: QueryOperator.greaterThanOrEqual,
            value: 18,
          ),
          QueryComparison(
            field: 'status',
            operator: QueryOperator.equal,
            value: 'active',
          ),
        ]),
        limit: 25,
        offset: 50,
      );

      expect(query.limit, 25);
      expect(query.offset, 50);
      expect((query.where as QueryGroup).filters, hasLength(2));
      expect(
        (query.where as QueryGroup).operator,
        QueryLogicalOperator.and,
      );
    });

    test('between requires an upper value', () {
      expect(
        () => QueryComparison(
          field: 'score',
          operator: QueryOperator.between,
          value: 10,
        ),
        throwsArgumentError,
      );
    });

    test('rejects malformed field paths', () {
      for (final field in <String>['', '.name', 'name.', 'profile..name']) {
        expect(
          () => QueryComparison(
            field: field,
            operator: QueryOperator.equal,
            value: 'Dxtr',
          ),
          throwsArgumentError,
        );
      }
    });

    test('requires non-empty boolean groups', () {
      expect(() => QueryGroup.and(const <QueryFilter>[]), throwsArgumentError);
      expect(() => QueryGroup.or(const <QueryFilter>[]), throwsArgumentError);
    });

    test('validates pagination', () {
      expect(
        () => BoxQuery(
          where: QueryComparison(
            field: 'age',
            operator: QueryOperator.equal,
            value: 18,
          ),
          limit: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => BoxQuery(
          where: QueryComparison(
            field: 'age',
            operator: QueryOperator.equal,
            value: 18,
          ),
          offset: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('index contract', () {
    test('supports a named scalar field index', () {
      final index = IndexDefinition(
        name: 'by-status',
        field: 'status',
      );

      expect(index.name, 'by-status');
      expect(index.field, 'status');
    });

    test('rejects unsafe index identifiers', () {
      expect(
        () => IndexDefinition(name: '1status', field: 'status'),
        throwsArgumentError,
      );
      expect(
        () => IndexDefinition(name: 'by status', field: 'status'),
        throwsArgumentError,
      );
    });
  });
}
