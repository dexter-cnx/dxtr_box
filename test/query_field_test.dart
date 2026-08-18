import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoxField', () {
    const status = BoxField<String>('status');
    const age = BoxField<int>('profile.age');
    const name = BoxField<String>('name');

    test('starts a typed standalone query and preserves the field path', () {
      final query = status.where().equals('active').build();

      final comparison = query.where as QueryComparison;
      expect(comparison.field, 'status');
      expect(comparison.operator, QueryOperator.equal);
      expect(comparison.value, 'active');
    });

    test('typed continuation compiles to the same existing AST', () {
      final query = status
          .where()
          .equals('active')
          .andField(age)
          .gte(18)
          .orderByField(name, descending: true)
          .limit(20)
          .build();

      final root = query.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      expect(root.filters, hasLength(2));

      final statusComparison = root.filters[0] as QueryComparison;
      final ageComparison = root.filters[1] as QueryComparison;
      expect(statusComparison.field, 'status');
      expect(statusComparison.value, 'active');
      expect(ageComparison.field, 'profile.age');
      expect(ageComparison.value, 18);

      expect(query.sortBy.single.field, 'name');
      expect(
        query.sortBy.single.direction,
        QuerySortDirection.descending,
      );
      expect(query.limit, 20);
    });

    test('supports typed fields inside explicit groups', () {
      final query = status
          .where()
          .equals('active')
          .andGroup(
            (group) =>
                group.whereField(age).gte(18).orField(name).equals('Ada'),
          )
          .build();

      final outer = query.where as QueryGroup;
      final nested = outer.filters.last as QueryGroup;
      expect((nested.filters.first as QueryComparison).field, 'profile.age');
      expect((nested.filters.last as QueryComparison).field, 'name');
    });

    test('box-bound typed entry point retains terminal find typing', () {
      Future<List<MapEntry<String, dynamic>>> execute(Box box) {
        return box
            .queryWhereField(status)
            .equals('active')
            .andField(age)
            .gte(18)
            .orderByField(name)
            .find();
      }

      expect(execute, isNotNull);
    });

    test('manual and typed-field forms are structurally equivalent', () {
      final typed = age
          .where()
          .between(18, 65)
          .orderByField(name)
          .offset(2)
          .limit(5)
          .build();

      final manual = BoxQuery(
        where: QueryComparison(
          field: 'profile.age',
          operator: QueryOperator.between,
          value: 18,
          upperValue: 65,
        ),
        sortBy: const <QuerySort>[
          QuerySort(field: 'name'),
        ],
        offset: 2,
        limit: 5,
      );

      final typedWhere = typed.where as QueryComparison;
      final manualWhere = manual.where as QueryComparison;
      expect(typedWhere.field, manualWhere.field);
      expect(typedWhere.operator, manualWhere.operator);
      expect(typedWhere.value, manualWhere.value);
      expect(typedWhere.upperValue, manualWhere.upperValue);
      expect(typed.sortBy.single.field, manual.sortBy.single.field);
      expect(typed.offset, manual.offset);
      expect(typed.limit, manual.limit);
    });

    test('string-path API remains first-class beside typed metadata', () {
      final stringQuery = BoxQueryBuilder.where(
        'status',
      ).equals('active').build();
      final typedQuery = status.where().equals('active').build();

      final stringComparison = stringQuery.where as QueryComparison;
      final typedComparison = typedQuery.where as QueryComparison;
      expect(typedComparison.field, stringComparison.field);
      expect(typedComparison.operator, stringComparison.operator);
      expect(typedComparison.value, stringComparison.value);
    });
  });
}
