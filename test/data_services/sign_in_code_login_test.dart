import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  var acceptsCode = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/functions/v1/exchange-sign-in-code') {
          return http.Response(
              jsonEncode(
                  acceptsCode ? {'refresh_token': 'fixture-refresh'} : {}),
              200,
              headers: {'content-type': 'application/json'});
        }
        // Stop at the Auth boundary; these tests create no session or user data.
        return http.Response(
            '{"error":"invalid_grant","error_description":"fixture stop"}', 400,
            headers: {'content-type': 'application/json'});
      }),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());
  setUp(() {
    requests.clear();
    acceptsCode = false;
  });

  test(
      'code exchange receives mailbox, password fallback keeps tenant identity',
      () async {
    const mailbox = 'person+tag@example.invalid';
    final identity = AppConfig.getUserPrefix(mailbox);
    await expectLater(
        AuthService.login(identity, '012345'), throwsA(isA<AuthException>()));
    expect(requests.map((r) => r.url.path).toList(),
        ['/functions/v1/exchange-sign-in-code', '/auth/v1/token']);
    expect(jsonDecode(requests.first.body), {
      'email': mailbox,
      'code': '012345',
      'organization': AppConfig.organization
    });
    expect(jsonDecode(requests.last.body)['email'], identity);
    expect(jsonDecode(requests.last.body)['password'], '012345');
  });

  test('accepted code refreshes returned session instead of password login',
      () async {
    acceptsCode = true;
    await expectLater(
        AuthService.login(
            AppConfig.getUserPrefix('person@example.invalid'), '123456'),
        throwsA(isA<AuthException>()));
    expect(requests.last.url.queryParameters['grant_type'], 'refresh_token');
    expect(jsonDecode(requests.last.body)['refresh_token'], 'fixture-refresh');
    expect(jsonDecode(requests.last.body).containsKey('password'), false);
  });

  test('ordinary password uses existing tenant-prefixed Auth login directly',
      () async {
    final identity = AppConfig.getUserPrefix('person@example.invalid');
    await expectLater(AuthService.login(identity, 'ordinary-password'),
        throwsA(isA<AuthException>()));
    expect(requests, hasLength(1));
    expect(requests.single.url.path, '/auth/v1/token');
    expect(jsonDecode(requests.single.body)['email'], identity);
  });
}
