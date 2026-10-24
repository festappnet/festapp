/// Take ownership of nested wire data at a snapshot boundary. Shared only by
/// modules that actually own JSON snapshots; contains no entities or UI state.
dynamic freezeJsonValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable(
      value.map(
        (key, value) => MapEntry(key as String, freezeJsonValue(value)),
      ),
    );
  }
  if (value is List)
    return List<dynamic>.unmodifiable(value.map(freezeJsonValue));
  return value;
}
