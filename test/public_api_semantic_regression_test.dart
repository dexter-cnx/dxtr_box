import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('query model compatibility', () {
    test('comparison operators preserve values and bounds', () {
      final comparison = QueryComparison(
        field: 'profile.age',
        operator: QueryOperator.between,
        value: 18,
        upperValue: 65,
      );

      expect(comparison.field, 'profile.age');
      expect(comparison.operator, QueryOperator.between);
      expect(comparison.value, 18);
      expect(comparison.upperValue, 65);
    });

    test('query groups and sort lists are immutable snapshots', () {
      final filters = <QueryFilter>[
        QueryComparison(
          field: 'active',
          operator: QueryOperator.equal,
          value: true,
        ),
      ];
      final sorts = <QuerySort>[QuerySort(field: 'name')];

      final group = QueryGroup.and(filters);
      final query = BoxQuery(where: group, sortBy: sorts);
      filters.clear();
      sorts.clear();

      expect(group.filters, hasLength(1));
      expect(query.sortBy, hasLength(1));
      expect(() => group.filters.clear(), throwsUnsupportedError);
      expect(() => query.sortBy.clear(), throwsUnsupportedError);
    });

    test('invalid query model inputs keep rejecting at construction time', () {
      expect(
        () => QueryComparison(
          field: '',
          operator: QueryOperator.equal,
          value: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => QueryComparison(
          field: 'age',
          operator: QueryOperator.between,
          value: 18,
        ),
        throwsArgumentError,
      );
      expect(() => QueryGroup.and(const <QueryFilter>[]), throwsArgumentError);
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
      expect(
        () => IndexDefinition(name: '1invalid', field: 'age'),
        throwsArgumentError,
      );
    });
  });

  group('fluent query compatibility', () {
    test('mixed logical chains remain left-associative', () {
      final query = BoxQueryBuilder.where('a')
          .equals(1)
          .or('b')
          .equals(2)
          .and('c')
          .equals(3)
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      expect(root.filters, hasLength(2));

      final left = root.filters.first as QueryGroup;
      expect(left.operator, QueryLogicalOperator.or);
      expect(left.filters, hasLength(2));
      expect((left.filters[0] as QueryComparison).field, 'a');
      expect((left.filters[1] as QueryComparison).field, 'b');
      expect((root.filters[1] as QueryComparison).field, 'c');
    });

    test('explicit grouping remains explicit in the compiled AST', () {
      final query = BoxQueryBuilder.where('a')
          .equals(1)
          .andGroup(
            (group) => group.where('b').equals(2).or('c').equals(3),
          )
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      final grouped = root.filters[1] as QueryGroup;
      expect(grouped.operator, QueryLogicalOperator.or);
      expect((grouped.filters[0] as QueryComparison).field, 'b');
      expect((grouped.filters[1] as QueryComparison).field, 'c');
    });

    test('result modifiers preserve ordering and validation semantics', () {
      final query = BoxQueryBuilder.where('active')
          .equals(true)
          .orderBy('name')
          .orderBy(
            'updatedAt',
            descending: true,
            nulls: QueryNullOrder.first,
          )
          .offset(5)
          .limit(10)
          .build();

      expect(query.offset, 5);
      expect(query.limit, 10);
      expect(query.sortBy, hasLength(2));
      expect(query.sortBy[0].field, 'name');
      expect(query.sortBy[0].direction, QuerySortDirection.ascending);
      expect(query.sortBy[0].nulls, QueryNullOrder.last);
      expect(query.sortBy[1].field, 'updatedAt');
      expect(query.sortBy[1].direction, QuerySortDirection.descending);
      expect(query.sortBy[1].nulls, QueryNullOrder.first);

      expect(
        () => BoxQueryBuilder.where('a').equals(1).offset(-1),
        throwsArgumentError,
      );
      expect(
        () => BoxQueryBuilder.where('a').equals(1).limit(0),
        throwsArgumentError,
      );
    });

    test('explicit groups reject result modifiers', () {
      expect(
        () => BoxQueryBuilder.where('a').equals(1).andGroup(
              (group) => group.where('b').equals(2).limit(1),
            ),
        throwsArgumentError,
      );
    });
  });
}
