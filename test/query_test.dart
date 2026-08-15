import 'package:dxtr_box/dxtr_box.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Dxtr query contract', () {
    test('supports nested field comparisons and pagination', () {
      final query = DxtrQuery(
        where: DxtrAnd(<DxtrCondition>[
          DxtrCompare(
            field: 'profile.age',
            operator: DxtrCompareOperator.greaterThanOrEqual,
            value: 18,
          ),
          DxtrCompare(
            field: 'status',
            operator: DxtrCompareOperator.equal,
            value: 'active',
          ),
        ]),
        limit: 25,
        offset: 50,
      );

      expect(query.limit, 25);
      expect(query.offset, 50);
      expect((query.where as DxtrAnd).conditions, hasLength(2));
    });

    test('between requires an upper value', () {
      expect(
        () => DxtrCompare(
          field: 'score',
          operator: DxtrCompareOperator.between,
          value: 10,
        ),
        throwsArgumentError,
      );
    });

    test('rejects malformed field paths', () {
      for (final field in <String>['', '.name', 'name.', 'profile..name']) {
        expect(
          () => DxtrCompare(
            field: field,
            operator: DxtrCompareOperator.equal,
            value: 'Dxtr',
          ),
          throwsArgumentError,
        );
      }
    });

    test('requires non-empty boolean groups', () {
      expect(() => DxtrAnd(const <DxtrCondition>[]), throwsArgumentError);
      expect(() => DxtrOr(const <DxtrCondition>[]), throwsArgumentError);
    });

    test('validates pagination', () {
      expect(
        () => DxtrQuery(
          where: DxtrCompare(
            field: 'age',
            operator: DxtrCompareOperator.equal,
            value: 18,
          ),
          limit: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => DxtrQuery(
          where: DxtrCompare(
            field: 'age',
            operator: DxtrCompareOperator.equal,
            value: 18,
          ),
          offset: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Dxtr index contract', () {
    test('supports a named scalar field index', () {
      final index = DxtrIndexDefinition(
        name: 'by-status',
        field: 'status',
      );

      expect(index.name, 'by-status');
      expect(index.field, 'status');
    });

    test('rejects unsafe index identifiers', () {
      expect(
        () => DxtrIndexDefinition(name: '1status', field: 'status'),
        throwsArgumentError,
      );
      expect(
        () => DxtrIndexDefinition(name: 'by status', field: 'status'),
        throwsArgumentError,
      );
    });
  });
}
