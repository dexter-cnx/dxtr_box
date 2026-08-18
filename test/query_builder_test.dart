import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fluent query builder', () {
    test('compiles comparisons to the existing BoxQuery AST', () {
      var builder = BoxQueryBuilder.where('status').equals('active');
      builder = builder.and('profile.age').gte(18);
      final query = builder.build();

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

      final operators = queries.map((query) {
        return (query.where as QueryComparison).operator;
      }).toList();

      expect(
        operators,
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

    test('compiles orderBy offset and limit to the existing BoxQuery AST', () {
      final query = BoxQueryBuilder.where('status')
          .equals('active')
          .orderBy('name')
          .orderBy(
            'profile.age',
            descending: true,
            nulls: QueryNullOrder.first,
          )
          .offset(10)
          .limit(20)
          .build();

      expect(query.sortBy, hasLength(2));
      expect(query.sortBy[0].field, 'name');
      expect(query.sortBy[0].direction, QuerySortDirection.ascending);
      expect(query.sortBy[0].nulls, QueryNullOrder.last);
      expect(query.sortBy[1].field, 'profile.age');
      expect(query.sortBy[1].direction, QuerySortDirection.descending);
      expect(query.sortBy[1].nulls, QueryNullOrder.first);
      expect(query.offset, 10);
      expect(query.limit, 20);
    });

    test('rejects invalid fluent offset and limit eagerly', () {
      final builder = BoxQueryBuilder.where('status').equals('active');

      expect(() => builder.offset(-1), throwsArgumentError);
      expect(() => builder.limit(0), throwsArgumentError);
      expect(() => builder.limit(-1), throwsArgumentError);
    });

    test('mixed AND/OR chains are left-associative', () {
      var builder = BoxQueryBuilder.where('a').equals(1);
      builder = builder.and('b').equals(2);
      builder = builder.or('c').equals(3);
      final query = builder.build();

      final outer = query.where as QueryGroup;
      expect(outer.operator, QueryLogicalOperator.or);
      expect(outer.filters, hasLength(2));

      final left = outer.filters.first as QueryGroup;
      expect(left.operator, QueryLogicalOperator.and);
      expect(left.filters, hasLength(2));
      expect((outer.filters.last as QueryComparison).field, 'c');
    });

    test('preserves result options while adding later predicates', () {
      var builder = BoxQueryBuilder.where('status')
          .equals('active')
          .orderBy('name')
          .offset(5)
          .limit(10);
      builder = builder.and('age').gte(18);
      final query = builder.build();

      expect(query.sortBy.single.field, 'name');
      expect(query.offset, 5);
      expect(query.limit, 10);
      expect((query.where as QueryGroup).filters, hasLength(2));
    });

    test('supports explicit nested groups', () {
      var builder = BoxQueryBuilder.where('status').equals('active');
      builder = builder.andGroup((group) {
        var nested = group.where('profile.age').gte(18);
        nested = nested.or('role').equals('admin');
        return nested;
      });
      final query = builder.build();

      final outer = query.where as QueryGroup;
      expect(outer.operator, QueryLogicalOperator.and);
      expect(outer.filters, hasLength(2));

      final nested = outer.filters.last as QueryGroup;
      expect(nested.operator, QueryLogicalOperator.or);
      expect((nested.filters.first as QueryComparison).field, 'profile.age');
      expect((nested.filters.last as QueryComparison).field, 'role');
    });

    test('rejects result modifiers inside explicit groups', () {
      final builder = BoxQueryBuilder.where('status').equals('active');

      expect(
        () => builder.andGroup(
          (group) => group.where('age').gte(18).orderBy('age'),
        ),
        throwsArgumentError,
      );
      expect(
        () => builder.andGroup(
          (group) => group.where('age').gte(18).offset(1),
        ),
        throwsArgumentError,
      );
      expect(
        () => builder.orGroup(
          (group) => group.where('role').equals('admin').limit(1),
        ),
        throwsArgumentError,
      );
    });

    test('keeps existing field validation behavior', () {
      expect(
        () => BoxQueryBuilder.where('profile..age').gte(18),
        throwsArgumentError,
      );
      expect(
        () => BoxQueryBuilder.where('status').equals('active').orderBy('x..y'),
        throwsArgumentError,
      );
    });

    test('box-bound path exposes terminal find with typed result', () {
      Future<List<MapEntry<String, dynamic>>> execute(Box box) {
        return box
            .queryWhere('status')
            .equals('active')
            .orderBy('name')
            .offset(2)
            .limit(5)
            .find();
      }

      expect(execute, isNotNull);
    });

    test('fluent and manual forms are structurally equivalent', () {
      var fluentBuilder = BoxQueryBuilder.where('status').equals('active');
      fluentBuilder = fluentBuilder.and('age').gte(18);
      final fluent = fluentBuilder
          .orderBy('name', descending: true)
          .offset(3)
          .limit(7)
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
        sortBy: <QuerySort>[
          QuerySort(
            field: 'name',
            direction: QuerySortDirection.descending,
          ),
        ],
        offset: 3,
        limit: 7,
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

      expect(fluent.sortBy.single.field, manual.sortBy.single.field);
      expect(
        fluent.sortBy.single.direction,
        manual.sortBy.single.direction,
      );
      expect(fluent.offset, manual.offset);
      expect(fluent.limit, manual.limit);
    });
  });
}
