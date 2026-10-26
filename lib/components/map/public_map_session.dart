import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fstapp/components/map/public_map_host.dart';
import 'package:fstapp/services/app_logger.dart';

enum MapVisitKind { returned, resolvedInPlace, cancelled, navigationFailed }

final class MapVisitResult {
  final MapVisitKind kind;
  final MapFocusOutcome outcome;

  const MapVisitResult._(this.kind, this.outcome);

  const MapVisitResult.returned(MapFocusOutcome outcome)
      : this._(MapVisitKind.returned, outcome);

  const MapVisitResult.resolvedInPlace(MapFocusOutcome outcome)
      : this._(MapVisitKind.resolvedInPlace, outcome);

  MapVisitResult.cancelled([String? reason])
      : this._(
          MapVisitKind.cancelled,
          MapFocusOutcome.cancelled(reason),
        );

  MapVisitResult.navigationFailed([String? reason])
      : this._(
          MapVisitKind.navigationFailed,
          MapFocusOutcome.failed(reason),
        );
}

enum PublicMapPhase { idle, waiting, applying, focused, failed, disposed }

abstract interface class MapTabNavigationAdapter {
  /// Activates the public map route and completes only when that route pops.
  Future<void> activateMap();

  /// Returns an active visit through the same retained tab router.
  Future<void> deactivateMap();
}

/// The sole occasion-scoped owner of public map intent orchestration.
class PublicMapSession extends ChangeNotifier {
  MapTabNavigationAdapter? _navigation;
  PublicMapHost? _host;
  MapIntent? _intent;
  int _requestId = 0;
  bool _visible = false;
  bool _disposed = false;
  PublicMapPhase _phase = PublicMapPhase.idle;
  MapFocusOutcome? _latestOutcome;
  String? _lastAttemptKey;
  int _effectGeneration = 0;
  Completer<MapVisitResult>? _activationCompleter;
  Completer<MapVisitResult>? _inPlaceCompleter;

  PublicMapPhase get phase => _phase;
  MapIntent? get intent => _intent;
  int get requestId => _requestId;
  bool get isMapVisible => _visible;
  MapFocusOutcome? get latestOutcome => _latestOutcome;
  bool get hasActivation => _activationCompleter != null;

  void bindNavigation(MapTabNavigationAdapter navigation) {
    _navigation = navigation;
  }

  void unbindNavigation(MapTabNavigationAdapter navigation) {
    if (identical(_navigation, navigation)) _navigation = null;
  }

  void attachHost(PublicMapHost host) {
    if (identical(_host, host)) return;
    _host = host;
    _lastAttemptKey = null;
    _tryApply();
  }

  void detachHost(PublicMapHost host) {
    if (!identical(_host, host)) return;
    _host = null;
    _effectGeneration++;
    _lastAttemptKey = null;
    if (_intent != null) _phase = PublicMapPhase.waiting;
  }

  void hostChanged() {
    if (_disposed) return;
    _publish();
    _tryApply();
  }

  void setVisible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    if (!visible) {
      _effectGeneration++;
      _lastAttemptKey = null;
      if (_intent != null) _phase = PublicMapPhase.waiting;
      final inPlace = _inPlaceCompleter;
      if (inPlace != null && !inPlace.isCompleted) {
        inPlace.complete(MapVisitResult.cancelled('mapBecameHidden'));
        _inPlaceCompleter = null;
      }
    }
    _publish();
    if (visible) _tryApply();
  }

  Future<MapVisitResult> openPlace(int placeId) =>
      _open(MapPlaceIntent(placeId));

  Future<MapVisitResult> openCategory(String placeType) =>
      _open(MapCategoryIntent(placeType));

  Future<bool> closeVisit() async {
    if (_disposed || !_visible || _activationCompleter == null) return false;
    final navigation = _navigation;
    if (navigation == null) return false;
    try {
      await navigation.deactivateMap();
      return true;
    } catch (error, stackTrace) {
      AppLogger.error(
          'Public map return navigation failed: $error\n$stackTrace');
      return false;
    }
  }

  /// Handles reselecting the already-visible Map tab. Pending focus work is
  /// invalidated before the retained host restores its canonical overview, so
  /// a late deep-link completion cannot move the camera back afterwards.
  Future<void> resetToOverview() async {
    if (_disposed || !_visible) return;
    _effectGeneration++;
    _intent = null;
    _latestOutcome = null;
    _lastAttemptKey = null;
    _phase = PublicMapPhase.idle;
    final inPlace = _inPlaceCompleter;
    if (inPlace != null && !inPlace.isCompleted) {
      inPlace.complete(MapVisitResult.cancelled('mapResetToOverview'));
    }
    _inPlaceCompleter = null;
    _publish();

    final host = _host;
    if (host == null) return;
    try {
      await host.resetToOverview();
    } catch (error, stackTrace) {
      AppLogger.error('Public map overview reset failed: $error\n$stackTrace');
    }
  }

  /// Thin cold-link adapter: routing already owns the active visit lifetime.
  void acceptExternalIntent(MapIntent intent) {
    if (_disposed) return;
    _publishIntent(intent);
  }

  Future<MapVisitResult> _open(MapIntent intent) {
    if (_disposed) {
      return Future.value(MapVisitResult.cancelled('sessionDisposed'));
    }
    final activeVisit = _activationCompleter;
    if (activeVisit != null && _sameIntent(_intent, intent)) {
      _tryApply();
      return activeVisit.future;
    }
    final inPlace = _inPlaceCompleter;
    if (inPlace != null && _sameIntent(_intent, intent)) {
      _tryApply();
      return inPlace.future;
    }
    _publishIntent(intent);

    if (_visible) {
      _inPlaceCompleter?.complete(
        MapVisitResult.cancelled('superseded'),
      );
      final completer = Completer<MapVisitResult>();
      _inPlaceCompleter = completer;
      _tryApply();
      return completer.future;
    }

    final existing = _activationCompleter;
    if (existing != null) {
      _tryApply();
      return existing.future;
    }

    final navigation = _navigation;
    if (navigation == null) {
      _phase = PublicMapPhase.failed;
      _publish();
      return Future.value(
        MapVisitResult.navigationFailed('mapNavigationUnavailable'),
      );
    }

    final activation = Completer<MapVisitResult>();
    _activationCompleter = activation;
    () async {
      try {
        await navigation.activateMap();
        if (_activationCompleter != activation || activation.isCompleted) {
          return;
        }
        _effectGeneration++;
        final outcome = _latestOutcome ??
            const MapFocusOutcome.cancelled('routePoppedBeforeFocus');
        activation.complete(MapVisitResult.returned(outcome));
      } catch (error, stackTrace) {
        AppLogger.error('Public map activation failed: $error\n$stackTrace');
        if (!activation.isCompleted) {
          activation.complete(
            MapVisitResult.navigationFailed(error.toString()),
          );
        }
      } finally {
        if (identical(_activationCompleter, activation)) {
          _activationCompleter = null;
          _intent = null;
          _latestOutcome = null;
          _lastAttemptKey = null;
          _phase = PublicMapPhase.idle;
          _publish();
        }
      }
    }();
    _tryApply();
    return activation.future;
  }

  bool _sameIntent(MapIntent? left, MapIntent right) => switch ((left, right)) {
        (
          MapPlaceIntent(:final placeId),
          MapPlaceIntent(placeId: final other)
        ) =>
          placeId == other,
        (
          MapCategoryIntent(:final placeType),
          MapCategoryIntent(placeType: final other)
        ) =>
          placeType == other,
        _ => false,
      };

  void _publishIntent(MapIntent intent) {
    _requestId++;
    _intent = intent;
    _latestOutcome = null;
    _lastAttemptKey = null;
    _effectGeneration++;
    _phase = PublicMapPhase.waiting;
    _publish();
  }

  void _tryApply() {
    final host = _host;
    final intent = _intent;
    if (_disposed || !_visible || host == null || intent == null) return;
    // A readiness or catalog notification may arrive after the current
    // request already reached a terminal result (for example while the place
    // dialog is opening). Those epochs only unlock a waiting/retryable
    // request; replaying a focused request would repeat its presentation
    // side effect and stack an identical dialog. A real host detach moves the
    // request back to waiting in detachHost(), so surface replacement still
    // restores the latest intent.
    if (_phase == PublicMapPhase.focused || _phase == PublicMapPhase.failed) {
      return;
    }
    final snapshot = host.snapshot;
    if (!snapshot.activeLayoutReady) {
      if (_phase != PublicMapPhase.waiting) {
        _phase = PublicMapPhase.waiting;
        _publish();
      }
      return;
    }
    final requestId = _requestId;
    final attemptKey = snapshot.attemptKey(requestId);
    if (_lastAttemptKey == attemptKey) return;
    _lastAttemptKey = attemptKey;
    _phase = PublicMapPhase.applying;
    final generation = ++_effectGeneration;
    _publish();
    final effect = PublicMapEffect(
      requestId: requestId,
      intent: intent,
      snapshot: snapshot,
    );
    () async {
      PublicMapHostResult result;
      try {
        result = await host.applyIntent(effect);
      } catch (error, stackTrace) {
        AppLogger.error('Public map focus failed: $error\n$stackTrace');
        result = PublicMapHostResult.failed(error.toString());
      }
      if (_disposed ||
          generation != _effectGeneration ||
          requestId != _requestId ||
          !identical(host, _host) ||
          host.snapshot.surfaceId != snapshot.surfaceId ||
          host.snapshot.styleEpoch != snapshot.styleEpoch) {
        return;
      }
      if (result.retryable) {
        _phase = PublicMapPhase.waiting;
        _publish();
        return;
      }
      _latestOutcome = result.outcome;
      _phase = result.outcome.status == MapFocusStatus.applied
          ? PublicMapPhase.focused
          : PublicMapPhase.failed;
      final inPlace = _inPlaceCompleter;
      if (inPlace != null && !inPlace.isCompleted) {
        inPlace.complete(MapVisitResult.resolvedInPlace(result.outcome));
        _inPlaceCompleter = null;
      }
      _publish();
    }();
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _phase = PublicMapPhase.disposed;
    _effectGeneration++;
    final cancelled = MapVisitResult.cancelled('sessionDisposed');
    if (!(_activationCompleter?.isCompleted ?? true)) {
      _activationCompleter!.complete(cancelled);
    }
    if (!(_inPlaceCompleter?.isCompleted ?? true)) {
      _inPlaceCompleter!.complete(cancelled);
    }
    _activationCompleter = null;
    _inPlaceCompleter = null;
    _host = null;
    _navigation = null;
    super.dispose();
  }
}

class PublicMapSessionScope extends InheritedNotifier<PublicMapSession> {
  const PublicMapSessionScope({
    required PublicMapSession session,
    required super.child,
    super.key,
  }) : super(notifier: session);

  PublicMapSession get session => notifier!;

  /// Command lookup deliberately avoids registering an inherited dependency.
  static PublicMapSession? read(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<PublicMapSessionScope>();
    return (element?.widget as PublicMapSessionScope?)?.session;
  }

  static PublicMapSession watch(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PublicMapSessionScope>()!
      .session;
}
