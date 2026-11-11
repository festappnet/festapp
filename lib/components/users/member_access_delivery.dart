import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tracks only receipt-bound messages and pending messages for selected members.
/// Polling is read-only, single-flight and bounded independently of network I/O.
class MemberAccessDelivery extends ChangeNotifier {
  MemberAccessDelivery({
    required this.readStatus,
    required this.isCurrent,
    this.selectedUserIds = const {},
  });

  static const observationWindow = Duration(minutes: 2);
  static const slowRequest = Duration(seconds: 15);
  final Future<Map<String, dynamic>> Function() readStatus;
  final bool Function() isCurrent;
  final Set<String> selectedUserIds;
  final Map<String, String> states = {};
  Map<String, dynamic>? status;
  bool readFailed = false;
  bool delayed = false;
  bool _stopped = false;
  bool _reading = false;
  bool _slow = false;
  int _attempt = 0;
  Future<void>? _inFlight;
  Timer? _poll;
  Timer? _window;
  Timer? _requestTimer;

  bool get reading => _reading;
  bool get showingLoading => _reading && !_slow;
  bool get hasPending => states.values.any((state) => !isTerminal(state));
  bool get watching => !_stopped && !delayed && _window != null && hasPending;
  int get delivered =>
      states.values.where((state) => state == 'delivered').length;

  static bool isTerminal(String state) =>
      const {'delivered', 'failed', 'cancelled', 'suppressed'}.contains(state);

  static String normalize(Object? state) =>
      const {
        'queued',
        'provider_accepted',
        'delivered',
        'failed',
        'cancelled',
        'suppressed',
        'dispatch_unresolved',
      }.contains(state)
      ? state as String
      : 'unknown';

  bool get _current => !_stopped && isCurrent();

  void track(Map<String, dynamic> receipt) {
    if (!_current) return;
    final communication = receipt['communication'];
    if (communication is! Map) return;
    final id = communication['messageId'];
    if (id is! String || id.isEmpty || states.containsKey(id)) return;
    states[id] = normalize(communication['state']);
    if (hasPending) _startWindow();
    notifyListeners();
    _schedule();
  }

  void _startWindow() {
    _window?.cancel();
    _poll?.cancel();
    delayed = false;
    _attempt = 0;
    _window = Timer(observationWindow, () {
      if (!_current) {
        stop();
        return;
      }
      _endWindow();
      delayed = hasPending;
      notifyListeners();
    });
  }

  Future<void> refresh({bool restart = false}) {
    if (!_current) {
      stop();
      return Future.value();
    }
    if (_inFlight != null) return _inFlight!;
    if (restart && hasPending) _startWindow();
    _poll?.cancel();
    return _inFlight = _load();
  }

  Future<void> _load() async {
    _reading = true;
    _slow = false;
    readFailed = false;
    _requestTimer = Timer(slowRequest, () {
      if (!_current) {
        stop();
        return;
      }
      // Do not start another HTTP request while this one is unresolved.
      _slow = true;
      readFailed = true;
      delayed = hasPending;
      _endWindow();
      notifyListeners();
    });
    notifyListeners();
    try {
      final value = await readStatus();
      if (!_current) {
        stop();
        return;
      }
      status = value;
      readFailed = false;
      var foundPendingSelection = false;
      for (final message
          in (value['messages'] as List? ?? []).whereType<Map>()) {
        final id = message['messageId'];
        if (id is! String) continue;
        final state = normalize(message['state']);
        if (!states.containsKey(id) &&
            selectedUserIds.contains(message['userId']) &&
            !isTerminal(state)) {
          states[id] = state;
          foundPendingSelection = true;
        } else if (states.containsKey(id)) {
          states[id] = state;
        }
      }
      if (foundPendingSelection && _window == null && !delayed) _startWindow();
      if (!hasPending) {
        _endWindow();
        delayed = false;
      }
    } catch (_) {
      if (!_current) {
        stop();
        return;
      }
      readFailed = true;
    } finally {
      _requestTimer?.cancel();
      _reading = false;
      _inFlight = null;
      if (_current) {
        notifyListeners();
        _schedule();
      }
    }
  }

  void _schedule() {
    if (!_current) {
      stop();
      return;
    }
    if (!watching || _reading) return;
    _poll?.cancel();
    final delay = _attempt == 0
        ? 2
        : _attempt < 3
        ? 5
        : 10;
    _poll = Timer(Duration(seconds: delay), () {
      _attempt++;
      unawaited(refresh());
    });
  }

  void _endWindow() {
    _poll?.cancel();
    _window?.cancel();
    _window = null;
  }

  void stop() {
    _stopped = true;
    _endWindow();
    _requestTimer?.cancel();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
