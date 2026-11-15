import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:festapp_core/program.dart' as occasion_time;
import 'package:fstapp/components/users/views/reset_password_page.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/root_supabase_fixture.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';
import '../../support/fixtures/rights_context_fixture.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

const destination = '/obnova2025-copy-2fb6f7b9/event';

class ResetRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      path: '/login',
      page: PageInfo(
        'Login',
        builder: (_) => const Scaffold(body: Text('Previous sign-in')),
      ),
    ),
    RedirectRoute(path: '/obnova2025-copy-2fb6f7b9', redirectTo: destination),
    AutoRoute(
      path: '/resetPassword',
      page: PageInfo(
        'Reset',
        builder: (_) => const ResetPasswordPage(
          token: '00000000-0000-4000-8000-000000000002',
        ),
      ),
    ),
    AutoRoute(
      path: destination,
      page: PageInfo(
        'Event',
        builder: (_) => const Scaffold(body: Text('Occasion program')),
      ),
    ),
    AutoRoute(
      path: '*',
      page: PageInfo(
        'Other',
        builder: (_) => const Scaffold(body: Text('Wrong destination')),
      ),
    ),
  ];
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
  });
  testWidgetsWithEnvironment(
    () => environment,
    'email password change replaces reset page with resolved occasion program',
    (tester) async {
      occasion_time.OccasionTimeContext.initializeTimeZones();
      final state = RightsContextFixture();
      addTearDown(state.dispose);
      final storage = (await tester.runAsync(LocalAppStorageFixture.open))!;
      addTearDown(storage.dispose);
      FlutterSecureStorage.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      const userId = '00000000-0000-4000-8000-000000000001';
      final jwt =
          '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600, 'sub': userId})))}.signature';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'),
            (_) async => true,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('PonnamKarthik/fluttertoast'),
              null,
            ),
      );
      var changes = 0;
      final fixture = (await tester.runAsync(
        () => RootSupabaseFixture.open((request) async {
          Object response = [];
          if (request.url.path.endsWith('/set_user_password_token')) {
            changes++;
            response = {'code': 200, 'email': 'person@example.com'};
          } else if (request.url.path == '/auth/v1/token') {
            response = {
              'access_token': jwt,
              'refresh_token': 'fixture-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': userId,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'person@example.com',
                'created_at': '2026-01-01T00:00:00Z',
              },
            };
          } else if (request.url.path == '/rest/v1/user_info') {
            response = [
              {'id': userId},
            ];
          } else if (request.url.path.contains('/get_app_config_')) {
            response = {
              'code': 200,
              'occasion': {'id': 98, 'link': 'obnova2025-copy-2fb6f7b9'},
              'user_info': {'id': userId},
              'organization': {'id': 6},
            };
          }
          return http.Response(
            jsonEncode(response),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      ))!;
      addTearDown(fixture.dispose);
      final router = ResetRouter();
      addTearDown(router.dispose);
      await environment.pumpWidget(
        tester,
        MaterialApp.router(
          builder: DependencyMaterialBridge.builder,
          routerConfig: router.config(
            deepLinkBuilder: (_) => DeepLink.path('/login'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.pushPath('/resetPassword'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'FixturePassword123!');
      await tester.runAsync(() async {
        await tester.tap(find.text(UserStrings.changePassword));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(router.urlState.uri.path, destination);
      expect(find.text('Occasion program'), findsOneWidget);
      expect(find.byType(ResetPasswordPage), findsNothing);
      await environment.pumpWidget(tester, const SizedBox.shrink());
    },
  );
}
