import 'dart:async';

/// Serializes reloads owned by one UI State without dropping a trigger that
/// arrives while another load is running.
class AsyncReloadCoordinator {
  Future<void>? _active;
  bool _requested = false;
  bool _disposed = false;

  bool get isLoading => _active != null;

  Future<void> run(Future<void> Function() reload) {
    if (_disposed) return Future.value();
    _requested = true;
    final active = _active;
    if (active != null) return active;

    late final Future<void> next;
    next = _drain(reload).whenComplete(() {
      if (identical(_active, next)) _active = null;
    });
    _active = next;
    return next;
  }

  Future<void> _drain(Future<void> Function() reload) async {
    while (_requested && !_disposed) {
      _requested = false;
      await reload();
    }
  }

  void dispose() {
    _disposed = true;
    _requested = false;
  }
}
