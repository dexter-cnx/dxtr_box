import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fluent query builder', () {
    test('compiles chained comparisons to the existing BoxQuery AST', () {
      final query = BoxQueryBuilder.where('status')
          .equals('active')
          .and('profile.age')
          .gte(18)
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

    test('supports every existing comparison operator', () {
      final queries = <BoxQuery>[
        BoxQueryBuilder.where('v').equals(1).build(),
        BoxQueryBuilder.where('v').notEquals(1).build(),
        BoxQueryBuilder.where('v').gt(1).build(),
        BoxQueryBuilder.where('v').gte(1).build(),
        BoxQueryBuilder.where('v').lt(1).build(),
        BoxQueryBuilder.where('v').lte(1).build(),
        BoxQueryBuilder.where('v').between(1, 10).build(),
        BoxQueryBuilder.where('v').isNull().build(),
        BoxQueryBuilder.where('v').isNotNull().build(),
      ];

      expect(
        queries
            .map((query) => (query.where as QueryComparison).operator)
            .toList(),
        <QueryOperator>[
          QueryOperator.equal,
          QueryOperator.notEqual,
          QueryOperator.greaterThan,
          QueryOperator.greaterThanOrEqual,
          QueryOperator.lessThan,
          QueryOperator.lessThanOrEqual,
          QueryOperator.between,
          QueryOperator.isNull,
          QueryOperator.isNotNull,
        ],
      );
    });

    test('mixed AND/OR chains are explicitly left-associative', () {
      final query = BoxQueryBuilder.where('a')
          .equals(1)
          .and('b')
          .equals(2)
          .or('c')
          .equals(3)
          .build();

      final outer = query.where as QueryGroup;
      expect(outer.operator, QueryLogicalOperator.or);
      expect(outer.filters, hasLength(2));

      final left = outer.filters.first as QueryGroup;
      expect(left.operator, QueryLogicalOperator.and);
      expect(left.filters, hasLength(2));
      expect((outer.filters.last as QueryComparison).field, 'c');
    });

    test('supports explicit nested groups', () {
      final query = BoxQueryBuilder.where('status')
          .equals('active')
          .andGroup(
            (group) => group
                .where('profile.age')
                .gte(18)
                .or('role')
                .equals('admin'),
          )
          .build();

      final outer = query.where as QueryGroup;
      expect(outer.operator, QueryLogicalOperator.and);
      expect(outer.filters, hasLength(2));

      final nested = outer.filters.last as QueryGroup;
      expect(nested.operator, QueryLogicalOperator.or);
      expect((nested.filters.first as QueryComparison).field, 'profile.age');
      expect((nested.filters.last as QueryComparison).field, 'role');
    });

    test('keeps existing field validation behavior', () {
      expect(
        () => BoxQueryBuilder.where('profile..age').gte(18),
        throwsArgumentError,
      );
    });

    test('fluent and manual forms are structurally equivalent', () {
      final fluent = BoxQueryBuilder.where('status')
          .equals('active')
          .and('age')
          .gte(18)
          .build();

      final manual = BoxQuery(
        where: QueryGroup.and(<QueryFilter>[
          QueryComparison(
            field: 'status',
            operator: QueryOperator.equal,
            value: 'active',
          ),
          QueryComparison(
            field: 'age',
            operator: QueryOperator.greaterThanOrEqual,
            value: 18,
          ),
        ]),
      );

      final fluentRoot = fluent.where as QueryGroup;
      final manualRoot = manual.where as QueryGroup;
      expect(fluentRoot.operator, manualRoot.operator);
      expect(fluentRoot.filters.length, manualRoot.filters.length);

      for (var i = 0; i < fluentRoot.filters.length; i++) {
        final actual = fluentRoot.filters[i] as QueryComparison;
        final expected = manualRoot.filters[i] as QueryComparison;
        expect(actual.field, expected.field);
        expect(actual.operator, expected.operator);
        expect(actual.value, expected.value);
        expect(actual.upperValue, expected.upperValue);
      }
    });
  });
}
