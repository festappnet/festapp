import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:http/http.dart' as http;

/// Global connectivity state shared by the offline banner and the pre-write
/// checks.
///
/// "Offline" here means *effectively unable to reach the backend* — not merely a
/// missing network interface. It is the OR of two signals:
///   1. the OS reports no network interface (connectivity_plus), and
///   2. the backend is unreachable — recent requests failed with network /
///      timeout / connection errors (weak signal, server outage, flaky net).
///
/// Backend reachability is observed passively from the outcome of the requests
/// the app already makes (via HealthTrackingHttpClient) and, while unreachable,
/// confirmed to recover by a lightweight active health probe — so the banner
/// clears reliably and never sticks.
class ConnectivityService {
  /// True while the app should present the offline UX (banner, degraded reads).
  static final ValueNotifier<bool> isOfflineNotifier = ValueNotifier(false);

  // --- inputs to the derived offline state ---
  static bool _interfaceOffline = false; // from connectivity_plus
  static bool _backendUnreachable = false; // from observed request outcomes

  /// Consecutive network failures with no intervening success. The banner only
  /// flips on at [_failuresToTrip] so a single transient blip never flashes it.
  static int _consecutiveFailures = 0;
  static const int _failuresToTrip = 2;

  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static Timer? _probeTimer;
  static Future<void>? _probeInFlight;
  static Future<void> Function()? _debugProbe;
  static const Duration _probeInterval = Duration(seconds: 12);
  static const Duration _probeTimeout = Duration(seconds: 5);
  static const Duration _startupProbeWait = Duration(milliseconds: 750);

  /// Public health endpoint that answers without auth; getting *any* response
  /// from it proves the backend is reachable again.
  static Uri _healthUri =
      Uri.parse('${AppConfig.effectiveSupabaseUrl}/auth/v1/health');

  /// Must be called before [initialize] when startup selected a transition
  /// backend. Supabase and the reachability probe then observe one origin.
  static void configureBackendOrigin(String origin) {
    if (_subscription != null) {
      throw StateError(
          'Backend origin cannot change after connectivity startup');
    }
    _healthUri = Uri.parse('$origin/auth/v1/health');
  }

  /// Starts the connectivity listener and seeds the interface state. Idempotent.
  static Future<void> initialize() async {
    if (_subscription != null) return;
    _subscription = Connectivity().onConnectivityChanged.listen((result) {
      _interfaceOffline = result.contains(ConnectivityResult.none);
      // A connectivity change often means recovery — probe right away so the
      // banner clears fast once the backend answers again.
      if (!_interfaceOffline && _backendUnreachable) {
        _probeNow();
      }
      _recompute();
    });
    try {
      final current = await Connectivity().checkConnectivity();
      _interfaceOffline = current.contains(ConnectivityResult.none);
    } catch (_) {
      // Keep the online default when the platform check is unavailable.
    }
    if (_interfaceOffline) {
      // iOS can briefly report `none` while its network monitor is warming up
      // after a restart. Give the authoritative backend probe a small window to
      // disprove that stale signal, without making a real offline start wait for
      // the full network timeout.
      await _probeNow().timeout(_startupProbeWait, onTimeout: () {});
    }
    _recompute();
  }

  /// A backend request completed (any HTTP status) → the server was reached, so
  /// the app is online. This is stronger evidence than a potentially stale OS
  /// interface report, therefore it clears both offline inputs immediately.
  static void reportSuccess() {
    _consecutiveFailures = 0;
    _interfaceOffline = false;
    _backendUnreachable = false;
    _stopProbe();
    _recompute();
  }

  /// A backend request failed with a network / timeout / connection error.
  /// After [_failuresToTrip] in a row, the backend is treated as unreachable.
  static void reportNetworkFailure() {
    _consecutiveFailures++;
    if (!_backendUnreachable && _consecutiveFailures >= _failuresToTrip) {
      _backendUnreachable = true;
      _startProbe();
      _recompute();
    }
  }

  /// One-shot check used right before a write. Refreshes the interface state and
  /// returns the derived offline value (interface down OR backend unreachable).
  static Future<bool> isOffline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _interfaceOffline = result.contains(ConnectivityResult.none);
      _recompute();
    } catch (_) {
      // Fall through to the last known derived state.
    }
    return isOfflineNotifier.value;
  }

  static void _recompute() {
    // ValueNotifier only notifies listeners when the value actually changes, so
    // the frequent reportSuccess() calls cause no spurious rebuilds.
    final wasOffline = isOfflineNotifier.value;
    isOfflineNotifier.value = _interfaceOffline || _backendUnreachable;
    if (wasOffline && !isOfflineNotifier.value) {
      unawaited(ClientSyncRuntime.connectivityRestored());
    }
  }

  static void _startProbe() {
    // Do not leave the UI in a stale offline state until the first periodic
    // tick. Startup/reload can produce a short burst of failed requests while
    // the native network stack is settling, even though the backend is already
    // reachable. One immediate, coalesced probe makes the backend response the
    // authoritative recovery signal.
    unawaited(_probeNow());
    _probeTimer ??= Timer.periodic(_probeInterval, (_) => _probeNow());
  }

  static void _stopProbe() {
    _probeTimer?.cancel();
    _probeTimer = null;
  }

  /// Actively checks whether the backend is reachable again — covers the case
  /// where the user is idle on cached data and issues no requests. Uses a plain
  /// client so it never re-enters the health tracker. Any response (even an
  /// error status) proves the server answered, so it clears the offline state.
  static Future<void> _probeNow() {
    return _probeInFlight ??= _performProbe().whenComplete(() {
      _probeInFlight = null;
    });
  }

  static Future<void> _performProbe() async {
    // Probe even when the platform currently reports no interface: that signal
    // can briefly be stale after reload/resume, while an actual backend response
    // is conclusive proof that the app is online.
    final debugProbe = _debugProbe;
    if (debugProbe != null) {
      try {
        await debugProbe();
        reportSuccess();
      } catch (_) {
        // A failed fake has the same meaning as an unreachable health endpoint.
      }
      return;
    }

    final client = http.Client();
    try {
      await client.get(_healthUri).timeout(_probeTimeout);
      reportSuccess();
    } catch (_) {
      // Still unreachable; the periodic timer will try again.
    } finally {
      client.close();
    }
  }

  /// Resets all state (test seam). Cancels the probe timer so tests leave no
  /// pending timers.
  @visibleForTesting
  static void debugReset() {
    _stopProbe();
    _subscription?.cancel();
    _subscription = null;
    _probeInFlight = null;
    _debugProbe = null;
    _healthUri = Uri.parse('${AppConfig.effectiveSupabaseUrl}/auth/v1/health');
    _interfaceOffline = false;
    _backendUnreachable = false;
    _consecutiveFailures = 0;
    isOfflineNotifier.value = false;
  }

  /// Simulates the platform connectivity signal without a method channel.
  @visibleForTesting
  static void debugSetInterfaceOffline(bool value) {
    _interfaceOffline = value;
    _recompute();
  }

  @visibleForTesting
  static void debugSetProbe(Future<void> Function() probe) {
    _debugProbe = probe;
  }
}
