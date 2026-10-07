import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
// Supabase's storage fixture uses its shared_preferences dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage =
      Directory.systemTemp.createTempSync('festapp-rights-context-');
  final contexts = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => storage.path);
    PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    tz.initializeTimeZones();
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        if (request.url.path.startsWith('/rest/v1/rpc/get_app_config_')) {
          final context = (jsonDecode(request.body)['data_in'] as Map)
              .cast<String, dynamic>();
          contexts.add(context);
          return http.Response(
              jsonEncode({
                'code': 200,
                if (context['unit_id'] == null)
                  'occasion': {
                    'id': 1072557,
                    'link': context['link'],
                    'data': {}
                  },
                if (context['unit_id'] != null)
                  'unit': {'id': context['unit_id']},
                'occasion_user': {'is_editor_view': true},
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        }
        throw StateError('Unexpected fixture request: ${request.url.path}');
      }),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    storage.deleteSync(recursive: true);
  });
  setUp(() {
    contexts.clear();
    RightsService.currentLink = null;
    RightsService.occasionLinkModelNotifier.value = null;
    RouterService.currentOccasionLink = '';
  });

  test('explicit administration link survives a configured landing occasion',
      () async {
    await RightsService.updateAppData(
        link: '2025we', force: true, refreshOffline: false);
    expect(contexts.single['link'], '2025we');
    expect(RightsService.currentLink, '2025we');
    expect(RightsService.canSeeAdministration(), isTrue);
  });

  test('unit administration does not send a forced occasion', () async {
    await RightsService.updateAppData(
        unitId: 999, force: true, refreshOffline: false);
    expect(contexts.single['unit_id'], 999);
    expect(contexts.single['link'], isNull);
  });

  test('implicit startup keeps the configured landing occasion', () async {
    if (AppConfig.forceOccasionLink == null) return;
    await RightsService.updateAppData(force: true, refreshOffline: false);
    expect(contexts.single['link'], AppConfig.forceOccasionLink);
  });
}
