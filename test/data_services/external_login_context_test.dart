import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'external login loads authenticated app config before reporting completion',
      () async {
    const userId = '00000000-0000-4000-8000-000000000001';
    final requests = <String>[];
    final storage =
        Directory.systemTemp.createTempSync('festapp-auth-context-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => storage.path);
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    tz.initializeTimeZones();
    final token =
        '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'sub': userId
        })))}.signature';
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      anonKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/auth/v1/token') {
          return http.Response(
              jsonEncode({
                'access_token': token,
                'refresh_token': 'fixture-refresh',
                'token_type': 'bearer',
                'expires_in': 3600,
                'user': {
                  'id': userId,
                  'aud': 'authenticated',
                  'role': 'authenticated',
                  'email': 'person@example.com',
                  'created_at': '2026-01-01T00:00:00Z',
                  'app_metadata': {},
                  'user_metadata': {}
                }
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        }
        if (request.url.path == '/rest/v1/user_info') {
          return http.Response(
              jsonEncode([
                {'id': userId}
              ]),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        }
        if (request.url.path.startsWith('/rest/v1/rpc/get_app_config_')) {
          expect(request.headers['authorization'], 'Bearer $token');
          return http.Response(
              jsonEncode({
                'code': 200,
                'user_info': {
                  'id': userId,
                  'units': [
                    {'id': 980, 'title': 'First'},
                    {'id': 981, 'title': 'Second'}
                  ]
                },
                'organization': {'title': 'Authenticated organization'}
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        }
        return http.Response('{}', 200,
            request: request, headers: {'content-type': 'application/json'});
      }),
    );
    try {
      RightsService.occasionLinkModelNotifier.value = null;
      await AuthService.completeExternalLogin({
        'organization': AppConfig.organization,
        'userId': userId,
        'session': {'refresh_token': 'fixture-refresh'}
      });
      expect(
          requests
              .where((path) => path.startsWith('/rest/v1/rpc/get_app_config_')),
          isNotEmpty);
      expect(RightsService.currentUser()?.id, userId);
      expect(RightsService.currentUser()?.units?.map((unit) => unit.id),
          [980, 981]);
      expect(RightsService.occasionLinkModel?.organization?.title,
          'Authenticated organization');
    } finally {
      await Supabase.instance.dispose();
      storage.deleteSync(recursive: true);
    }
  });
}
