/// Serializes read-marker updates while retaining a request that arrives during
/// an in-flight mutation. The callbacks intentionally read current page state
/// on every pass so a newer message is acknowledged immediately afterwards.
class NewsReadCoordinator {
  Future<void>? _active;
  bool _requested = false;
  bool _disposed = false;

  Future<void> acknowledgeLatest({
    required bool Function() isVisible,
    required bool Function() isLoggedIn,
    required int? Function() latestUnreadId,
    required Future<void> Function(int id) persist,
    required void Function(int id) markLocally,
  }) {
    if (_disposed) return Future.value();
    _requested = true;
    final active = _active;
    if (active != null) return active;

    late final Future<void> next;
    next = _drain(
      isVisible: isVisible,
      isLoggedIn: isLoggedIn,
      latestUnreadId: latestUnreadId,
      persist: persist,
      markLocally: markLocally,
    ).whenComplete(() {
      if (identical(_active, next)) _active = null;
    });
    _active = next;
    return next;
  }

  Future<void> _drain({
    required bool Function() isVisible,
    required bool Function() isLoggedIn,
    required int? Function() latestUnreadId,
    required Future<void> Function(int id) persist,
    required void Function(int id) markLocally,
  }) async {
    while (_requested && !_disposed) {
      _requested = false;
      if (!isVisible() || !isLoggedIn()) continue;
      final id = latestUnreadId();
      if (id == null) continue;
      await persist(id);
      if (_disposed) return;
      markLocally(id);
    }
  }

  void dispose() {
    _disposed = true;
    _requested = false;
  }
}
