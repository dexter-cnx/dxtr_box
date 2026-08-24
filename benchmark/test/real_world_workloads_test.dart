import 'package:flutter_test/flutter_test.dart';

import '../lib/real_world_workloads.dart';

void main() {
  group('settings/session workload', () {
    test('is deterministic and contains expected hot keys', () {
      expect(settingsSessionFixture(), settingsSessionFixture());
      expect(
        settingsSessionFixture().keys,
        containsAll(<String>[
          'theme',
          'locale',
          'feature_flags',
          'active_workspace',
          'session',
        ]),
      );
    });
  });

  group('catalog/workspace workload', () {
    test('is deterministic and preserves application-shaped fields', () {
      final first = catalogWorkspaceFixture(128);
      final second = catalogWorkspaceFixture(128);

      expect(first, second);
      expect(first, hasLength(128));
      expect(first.keys.first, 'item-000000');
      expect(first.keys.last, 'item-000127');
      expect(first['item-000010']!['status'], 'archived');
      expect(first['item-000011']!['status'], 'active');
      expect(first['item-000011']!['metadata'], isA<Map<String, Object?>>());
      expect((first['item-000011']!['payload']! as String).length, 192);
    });

    test('hot-key selection is bounded and stable', () {
      expect(catalogHotKeys(3), <String>[
        'item-000000',
        'item-000001',
        'item-000002',
      ]);
      expect(catalogHotKeys(1000, limit: 100), hasLength(100));
      expect(catalogHotKeys(0), isEmpty);
    });
  });

  group('activity/event workload', () {
    test('is deterministic and append ordered', () {
      final events = activityEventFixture(32);

      expect(events, activityEventFixture(32));
      expect(events.keys.first, 'event-00000000');
      expect(events.keys.last, 'event-00000031');
      expect(events['event-00000000']!['sequence'], 0);
      expect(events['event-00000031']!['sequence'], 31);
    });

    test('retention deletes a deterministic oldest prefix', () {
      expect(
        activityRetentionDeleteKeys(8),
        <String>['event-00000000', 'event-00000001'],
      );
      expect(
        activityRetentionDeleteKeys(10, deleteFraction: 0.5),
        <String>[
          'event-00000000',
          'event-00000001',
          'event-00000002',
          'event-00000003',
          'event-00000004',
        ],
      );
    });
  });

  test('invalid workload sizes are rejected', () {
    expect(() => catalogWorkspaceFixture(-1), throwsArgumentError);
    expect(() => activityEventFixture(-1), throwsArgumentError);
    expect(() => catalogHotKeys(-1), throwsArgumentError);
    expect(
      () => activityRetentionDeleteKeys(10, deleteFraction: 1.1),
      throwsArgumentError,
    );
  });
}
