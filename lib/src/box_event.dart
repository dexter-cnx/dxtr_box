enum BoxEventType { put, delete, clear }

final class BoxEvent {
  const BoxEvent({
    required this.boxName,
    required this.type,
    this.key,
    this.value,
  });

  final String boxName;
  final BoxEventType type;
  final String? key;
  final dynamic value;

  @override
  String toString() =>
      'BoxEvent(boxName: $boxName, type: $type, key: $key, value: $value)';
}
