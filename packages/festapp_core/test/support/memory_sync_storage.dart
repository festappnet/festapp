import 'package:festapp_core/sync.dart';

/// In-memory implementation of the real atomic storage port, with fault injection
/// at commit. Failed commits leave all values and other scopes intact.
class MemorySyncStorage implements ClientSyncStorage {
  final values = <String, String>{};
  bool failNextCommit = false;

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<List<String>> keys() async => values.keys.toList();

  @override
  Future<void> replaceAtomic(
    Map<String, String?> writes, {
    List<String> removePrefixes = const [],
  }) async {
    final next = Map<String, String>.from(values);
    next.removeWhere((key, _) => removePrefixes.any(key.startsWith));
    for (final entry in writes.entries) {
      if (entry.value == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value!;
      }
    }
    if (failNextCommit) {
      failNextCommit = false;
      throw StateError('Injected storage commit failure');
    }
    values
      ..clear()
      ..addAll(next);
  }
}
