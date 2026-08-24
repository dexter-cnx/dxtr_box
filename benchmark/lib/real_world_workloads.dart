typedef WorkloadRecord = Map<String, Object?>;

const int _baseTimestampMs = 1700000000000;

Map<String, WorkloadRecord> settingsSessionFixture() =>
    <String, WorkloadRecord>{
      'theme': <String, Object?>{'value': 'dark', 'updated_at': 1},
      'locale': <String, Object?>{'value': 'th_TH', 'updated_at': 2},
      'feature_flags': <String, Object?>{
        'value': <String, Object?>{
          'fast_search': true,
          'compact_cards': false,
          'offline_mode': true,
        },
        'updated_at': 3,
      },
      'active_workspace': <String, Object?>{
        'value': 'workspace-0003',
        'updated_at': 4,
      },
      'session': <String, Object?>{
        'value': <String, Object?>{
          'user_id': 'user-local',
          'last_route': '/workspace',
          'launch_count': 42,
        },
        'updated_at': 5,
      },
    };

Map<String, WorkloadRecord> catalogWorkspaceFixture(int count) {
  if (count < 0) {
    throw ArgumentError.value(count, 'count', 'must be non-negative');
  }

  return <String, WorkloadRecord>{
    for (var index = 0; index < count; index++)
      'item-${index.toString().padLeft(6, '0')}': <String, Object?>{
        'id': index,
        'name': 'Asset ${index.toString().padLeft(6, '0')}',
        'status': index % 10 == 0 ? 'archived' : 'active',
        'category': 'category-${index % 8}',
        'score': (index * 37) % 1000,
        'captured_at': _baseTimestampMs + (index * 1000),
        'metadata': <String, Object?>{
          'workspace_id': 'workspace-${index % 5}',
          'source': index.isEven ? 'camera' : 'import',
          'favorite': index % 17 == 0,
        },
        'payload': _payload(index, 192),
      },
  };
}

Map<String, WorkloadRecord> activityEventFixture(int count) {
  if (count < 0) {
    throw ArgumentError.value(count, 'count', 'must be non-negative');
  }

  return <String, WorkloadRecord>{
    for (var index = 0; index < count; index++)
      'event-${index.toString().padLeft(8, '0')}': <String, Object?>{
        'sequence': index,
        'event_type': switch (index % 4) {
          0 => 'created',
          1 => 'updated',
          2 => 'viewed',
          _ => 'synced_local',
        },
        'timestamp': _baseTimestampMs + (index * 250),
        'actor': <String, Object?>{
          'id': 'actor-${index % 7}',
          'source': index % 3 == 0 ? 'background' : 'foreground',
        },
        'payload': <String, Object?>{
          'target_id': 'item-${(index % 1000).toString().padLeft(6, '0')}',
          'revision': index % 13,
          'note': _payload(index, 48),
        },
      },
  };
}

List<String> catalogHotKeys(int recordCount, {int limit = 100}) {
  if (recordCount < 0) {
    throw ArgumentError.value(
      recordCount,
      'recordCount',
      'must be non-negative',
    );
  }
  if (limit < 0) {
    throw ArgumentError.value(limit, 'limit', 'must be non-negative');
  }

  final selected = recordCount < limit ? recordCount : limit;
  return List<String>.generate(
    selected,
    (index) => 'item-${index.toString().padLeft(6, '0')}',
    growable: false,
  );
}

List<String> activityRetentionDeleteKeys(
  int recordCount, {
  double deleteFraction = 0.25,
}) {
  if (recordCount < 0) {
    throw ArgumentError.value(
      recordCount,
      'recordCount',
      'must be non-negative',
    );
  }
  if (deleteFraction < 0 || deleteFraction > 1) {
    throw ArgumentError.value(
      deleteFraction,
      'deleteFraction',
      'must be between 0 and 1',
    );
  }

  final deleteCount = (recordCount * deleteFraction).floor();
  return List<String>.generate(
    deleteCount,
    (index) => 'event-${index.toString().padLeft(8, '0')}',
    growable: false,
  );
}

String _payload(int seed, int length) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final buffer = StringBuffer();
  for (var index = 0; index < length; index++) {
    buffer.write(alphabet[(seed + index) % alphabet.length]);
  }
  return buffer.toString();
}
