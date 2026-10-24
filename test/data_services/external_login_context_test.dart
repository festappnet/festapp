import '../support/fixtures/root_supabase_fixture.dart';
import '../support/fixtures/local_app_storage_fixture.dart';
import '../support/fixtures/rights_context_fixture.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'external login loads authenticated app config before reporting completion',
      () async {
    const userId = '00000000-0000-4000-8000-000000000001';
    final requests = <String>[];
    tz.initializeTimeZones();
    final state = RightsContextFixture();
    addTearDown(state.dispose);
    final storage = await LocalAppStorageFixture.open();
    addTearDown(storage.dispose);
    FlutterSecureStorage.setMockInitialValues({});
    addTearDown(() => const FlutterSecureStorage().deleteAll());
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    final token =
        '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'sub': userId
        })))}.signature';
    final fixture = await RootSupabaseFixture.open((request) async {
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
    });
    addTearDown(fixture.dispose);
    {
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
    }
  });
}
