import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/services/notification_helper.dart';

class _FakeAudienceClient implements NotificationAudienceClient {
  final addedTags = <Map<String, String>>[];
  final logins = <String>[];
  var optInCount = 0;
  var logoutCount = 0;

  @override
  Future<void> addTags(Map<String, String> tags) async =>
      addedTags.add(Map.of(tags));

  @override
  Future<void> login(String externalId) async => logins.add(externalId);

  @override
  Future<void> optIn() async => optInCount++;

  @override
  Future<void> logout() async => logoutCount++;
}

void main() {
  late _FakeAudienceClient client;
  late bool supported;
  late bool permitted;
  late bool loggedIn;
  late NotificationAudienceCoordinator coordinator;

  setUp(() {
    client = _FakeAudienceClient();
    supported = true;
    permitted = true;
    loggedIn = false;
    coordinator = NotificationAudienceCoordinator(
      client: client,
      notificationsSupported: () => supported,
      notificationPermission: () => permitted,
      isLoggedIn: () => loggedIn,
      currentUserId: () => 'user-uuid',
      occasionLink: () => 'csmostrava2026',
      installationGeneration: 'csm_ostrava_2026_v1',
    );
  });

  test('tags an anonymous opted-in CSM subscription', () async {
    await coordinator.tagCurrentSubscription();
    await coordinator.loginCurrentUser();

    expect(client.addedTags, [
      {'app_generation': 'csm_ostrava_2026_v1', 'occasion': 'csmostrava2026'},
    ]);
    expect(client.logins, isEmpty);
  });

  test(
    'authenticated identity login is separate from subscription tags',
    () async {
      loggedIn = true;

      await coordinator.loginCurrentUser();

      expect(client.logins, ['user-uuid']);
      expect(client.addedTags, isEmpty);
    },
  );

  test('permission blocks tags but not authenticated identity login', () async {
    permitted = false;
    loggedIn = true;

    await coordinator.tagCurrentSubscription();
    await coordinator.loginCurrentUser();

    expect(client.addedTags, isEmpty);
    expect(client.logins, ['user-uuid']);
  });

  test(
    'logout clears a stale external identity without an auth session',
    () async {
      await coordinator.logoutCurrentUser();

      expect(client.logoutCount, 1);
    },
  );

  test(
    'omits tenant generation and empty occasion when not configured',
    () async {
      coordinator = NotificationAudienceCoordinator(
        client: client,
        notificationsSupported: () => supported,
        notificationPermission: () => permitted,
        isLoggedIn: () => loggedIn,
        currentUserId: () => 'user-uuid',
        occasionLink: () => '',
        installationGeneration: '',
      );

      await coordinator.tagCurrentSubscription();

      expect(client.addedTags, isEmpty);
    },
  );

  test('does not write a partial tenant audience', () async {
    coordinator = NotificationAudienceCoordinator(
      client: client,
      notificationsSupported: () => supported,
      notificationPermission: () => permitted,
      isLoggedIn: () => loggedIn,
      currentUserId: () => 'user-uuid',
      occasionLink: () => 'csmostrava2026',
      installationGeneration: '',
    );

    await coordinator.tagCurrentSubscription();

    expect(client.addedTags, isEmpty);
  });

  test('activates the complete audience immediately after permission grant',
      () async {
    loggedIn = true;

    await coordinator.activateCurrentInstallation();

    expect(client.optInCount, 1);
    expect(client.addedTags, [
      {'app_generation': 'csm_ostrava_2026_v1', 'occasion': 'csmostrava2026'},
    ]);
    expect(client.logins, ['user-uuid']);
  });

  test('retries notification initialization when an offline start reconnects',
      () async {
    var initializeCount = 0;
    final reconnect = NotificationReconnectCoordinator(
      startsOffline: true,
      initialize: () async => initializeCount++,
    );

    await reconnect.connectivityChanged(true);
    await reconnect.connectivityChanged(false);
    await reconnect.connectivityChanged(false);

    expect(initializeCount, 1);
  });
}
