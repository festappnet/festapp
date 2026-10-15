import 'dart:async';

/// A fixture owns only the resources it acquired. Cleanup runs in reverse order
/// and attempts every disposer even when a previous disposer failed.
class FixtureScope {
  final _disposers = <FutureOr<void> Function()>[];
  bool _disposed = false;
  void onDispose(FutureOr<void> Function() disposer) {
    if (_disposed) throw StateError('Fixture has already been disposed');
    _disposers.add(disposer);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final failures = <Object>[];
    for (final disposer in _disposers.reversed) {
      try {
        await disposer();
      } catch (error) {
        failures.add(error);
      }
    }
    _disposers.clear();
    if (failures.isNotEmpty) throw FixtureCleanupException(failures);
  }
}

class FixtureCleanupException implements Exception {
  FixtureCleanupException(List<Object> failures)
      : failures = List.unmodifiable(failures);
  final List<Object> failures;
  @override
  String toString() => 'Fixture cleanup failed: ${failures.join('; ')}';
}
