import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/connectivity_service.dart';

/// Verifies the backend-reachability state machine that drives the offline
/// banner: a single network blip must not flip it, two in a row must, and any
/// success clears it immediately. These are pure state transitions — no
/// platform channels or network involved.
void main() {
  setUp(() {
    ConnectivityService.debugReset();
    ConnectivityService.debugSetProbe(
      () => Future<void>.error(StateError('backend unavailable')),
    );
  });
  tearDown(ConnectivityService.debugReset);

  test('a single network failure does not flip to offline', () {
    ConnectivityService.reportNetworkFailure();
    expect(ConnectivityService.isOfflineNotifier.value, isFalse);
  });

  test('two consecutive network failures flip to offline', () {
    ConnectivityService.reportNetworkFailure();
    ConnectivityService.reportNetworkFailure();
    expect(ConnectivityService.isOfflineNotifier.value, isTrue);
  });

  test('a success clears the offline state immediately', () {
    ConnectivityService.reportNetworkFailure();
    ConnectivityService.reportNetworkFailure();
    expect(ConnectivityService.isOfflineNotifier.value, isTrue);

    ConnectivityService.reportSuccess();
    expect(ConnectivityService.isOfflineNotifier.value, isFalse);
  });

  test('a backend success overrides a stale platform offline signal', () {
    ConnectivityService.debugSetInterfaceOffline(true);
    expect(ConnectivityService.isOfflineNotifier.value, isTrue);

    ConnectivityService.reportSuccess();

    expect(ConnectivityService.isOfflineNotifier.value, isFalse);
  });

  test('a success between failures resets the streak (no flip)', () {
    ConnectivityService.reportNetworkFailure();
    ConnectivityService.reportSuccess();
    ConnectivityService.reportNetworkFailure();
    expect(ConnectivityService.isOfflineNotifier.value, isFalse);
  });

  test('entering offline probes immediately and clears a stale state',
      () async {
    ConnectivityService.debugSetProbe(() async {});

    ConnectivityService.reportNetworkFailure();
    ConnectivityService.reportNetworkFailure();
    expect(ConnectivityService.isOfflineNotifier.value, isTrue);

    await Future<void>.delayed(Duration.zero);
    expect(ConnectivityService.isOfflineNotifier.value, isFalse);
  });
}
