import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'internal recovery handoff installs original UUID without recovery UI in Flutter SDK',
      () async {
    final env = Platform.environment;
    final url = Uri.parse(env['FESTAPP_FIXTURE_AUTH_URL']!);
    expect(url.host, '127.0.0.1');
    final client = GoTrueClient(
        url: url.toString(),
        headers: {'apikey': env['FESTAPP_FIXTURE_ANON_KEY']!},
        autoRefreshToken: false);
    final events = <AuthChangeEvent>[];
    final listener =
        client.onAuthStateChange.listen((event) => events.add(event.event));
    try {
      final installed =
          await client.setSession(env['FESTAPP_FIXTURE_REFRESH_TOKEN']!);
      expect(installed.user?.id, env['FESTAPP_FIXTURE_USER_ID']);
      expect(events, isNot(contains(AuthChangeEvent.passwordRecovery)));
      final refreshed = await client.refreshSession();
      expect(refreshed.user?.id, env['FESTAPP_FIXTURE_USER_ID']);
      await client.signOut(scope: SignOutScope.local);
    } finally {
      await listener.cancel();
      client.dispose();
    }
  }, skip: Platform.environment['FESTAPP_FIXTURE_AUTH_URL'] == null);
}
