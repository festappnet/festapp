import '../support/fixtures/root_supabase_fixture.dart';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final requests = <http.Request>[];
  late RootSupabaseFixture fixture;
  var acceptsCode = false;
  var exchangeUnavailable = false;
  setUpAll(() async {
    fixture = await RootSupabaseFixture.open((request) async {
      requests.add(request);
      if (request.url.path == '/functions/v1/exchange-sign-in-code') {
        if (exchangeUnavailable) {
          return http.Response(
            '{"error":"auth_temporarily_unavailable"}',
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(acceptsCode ? {'refresh_token': 'fixture-refresh'} : {}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      // Stop at the Auth boundary; these tests create no session or user data.
      return http.Response(
        '{"error":"invalid_grant","error_description":"fixture stop"}',
        400,
        headers: {'content-type': 'application/json'},
      );
    });
  });
  tearDownAll(() => fixture.dispose());
  setUp(() {
    requests.clear();
    acceptsCode = false;
    exchangeUnavailable = false;
  });

  test(
    'code exchange receives mailbox, password fallback keeps tenant identity',
    () async {
      const mailbox = 'person+tag@example.invalid';
      final identity = AppConfig.getUserPrefix(mailbox);
      await expectLater(
        AuthService.login(identity, '012345'),
        throwsA(isA<AuthException>()),
      );
      expect(requests.map((r) => r.url.path).toList(), [
        '/functions/v1/exchange-sign-in-code',
        '/auth/v1/token',
      ]);
      expect(jsonDecode(requests.first.body), {
        'email': mailbox,
        'code': '012345',
        'organization': AppConfig.organization,
      });
      expect(jsonDecode(requests.last.body)['email'], identity);
      expect(jsonDecode(requests.last.body)['password'], '012345');
    },
  );

  test(
    'accepted code refreshes returned session instead of password login',
    () async {
      acceptsCode = true;
      await expectLater(
        AuthService.login(
          AppConfig.getUserPrefix('person@example.invalid'),
          '123456',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(requests.last.url.queryParameters['grant_type'], 'refresh_token');
      expect(
        jsonDecode(requests.last.body)['refresh_token'],
        'fixture-refresh',
      );
      expect(jsonDecode(requests.last.body).containsKey('password'), false);
    },
  );

  test(
    'unavailable code exchange does not silently attempt password login',
    () async {
      exchangeUnavailable = true;
      await expectLater(
        AuthService.login(
          AppConfig.getUserPrefix('person@example.invalid'),
          '123456',
        ),
        throwsA(isA<FunctionException>()),
      );
      expect(requests.map((r) => r.url.path), [
        '/functions/v1/exchange-sign-in-code',
      ]);
    },
  );

  test(
    'ordinary password uses existing tenant-prefixed Auth login directly',
    () async {
      final identity = AppConfig.getUserPrefix('person@example.invalid');
      await expectLater(
        AuthService.login(identity, 'ordinary-password'),
        throwsA(isA<AuthException>()),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/auth/v1/token');
      expect(jsonDecode(requests.single.body)['email'], identity);
    },
  );
}
