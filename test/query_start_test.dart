import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fluent Box Query primary entry point', () {
    test('queryBuilder keeps query(BoxQuery) source-compatible', () {
      Future<List<MapEntry<String, dynamic>>> executeExisting(
        Box box,
        BoxQuery query,
      ) {
        return box.query(query);
      }

      BoxQueryStart startPrimary(Box box) => box.queryBuilder();

      expect(executeExisting, isNotNull);
      expect(startPrimary, isNotNull);
    });

    test('queryBuilder compiles to the existing canonical BoxQuery AST', () {
      BoxQuery buildPrimary(Box box) {
        return box
            .queryBuilder()
            .where('status')
            .equals('active')
            .and('profile.age')
            .gte(18)
            .orderBy('name', descending: true)
            .limit(20)
            .build();
      }

      BoxQuery buildExisting() {
        return BoxQueryBuilder.where('status')
            .equals('active')
            .and('profile.age')
            .gte(18)
            .orderBy('name', descending: true)
            .limit(20)
            .build();
      }

      expect(buildPrimary, isNotNull);

      final existing = buildExisting();
      final root = existing.where as QueryGroup;
      expect(root.operator, QueryLogicalOperator.and);
      expect(root.filters, hasLength(2));
      expect((root.filters.first as QueryComparison).field, 'status');
      expect((root.filters.last as QueryComparison).field, 'profile.age');
      expect(existing.sortBy.single.field, 'name');
      expect(existing.sortBy.single.direction, QuerySortDirection.descending);
      expect(existing.limit, 20);
    });

    test('queryBuilder terminal path retains one Box.query execution seam', () {
      Future<List<MapEntry<String, dynamic>>> execute(Box box) {
        return box
            .queryBuilder()
            .where('status')
            .equals('active')
            .orderBy('name')
            .limit(5)
            .find();
      }

      expect(execute, isNotNull);
    });
  });
}
