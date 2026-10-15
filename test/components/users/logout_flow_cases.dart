import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/logout_flow.dart';

void main() {
  test('notification cleanup failure cannot keep the local session signed in',
      () async {
    final events = <String>[];

    await runLogoutFlow(
      detachNotifications: () async => throw Exception('push unavailable'),
      clearPrivateData: () async => events.add('private-data-cleared'),
      signOutLocal: () async => events.add('session-cleared'),
      resetIdentity: () async => events.add('identity-cleared'),
      clearRefreshToken: () async => events.add('refresh-token-cleared'),
      clearRights: () => events.add('rights-cleared'),
    );

    expect(events, [
      'session-cleared',
      'refresh-token-cleared',
      'private-data-cleared',
      'identity-cleared',
      'rights-cleared',
    ]);
  });
}
