import 'dart:convert';
import 'package:fstapp/services/auth_session_storage.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores the JS Google session before authenticated admin requests',
      () async {
    const key = 'shared-auth-session';
    final expiry = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    final token = [
      base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', ''),
      base64Url
          .encode(utf8.encode(jsonEncode({'exp': expiry})))
          .replaceAll('=', ''),
      'signature',
    ].join('.');
    final session = jsonEncode({
      'access_token': token,
      'refresh_token': 'existing-google-refresh',
      'token_type': 'bearer',
      // supabase-js setSession subtracts Date.now()/1000 from JWT exp.
      'expires_in': 3599.417,
      'expires_at': expiry,
      'user': {
        'id': 'original-account',
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-02T00:00:00Z'
      },
    });
    SharedPreferences.setMockInitialValues({key: session});
    final storage = AuthSessionStorage(persistSessionKey: key);
    await storage.initialize();
    final client = GoTrueClient(
      url: 'http://127.0.0.1:1/auth/v1',
      autoRefreshToken: false,
    );
    try {
      await client.setInitialSession((await storage.accessToken())!);
      expect(client.currentUser?.id, 'original-account');
      expect(client.currentSession?.accessToken, token);
      expect(client.currentSession?.refreshToken, 'existing-google-refresh');
      expect(client.currentSession?.expiresIn, 3599);
    } finally {
      client.dispose();
    }
  });
}
