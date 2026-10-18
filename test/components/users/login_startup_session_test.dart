import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// Test the Supabase SDK's shared-preferences storage boundary.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/user_strings.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  TestWidgetsFlutterBinding.ensureInitialized();
  late Completer<http.Response> contextLoad;
  late List<String> requests;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
    contextLoad = Completer<http.Response>();
    requests = [];
    await Supabase.initialize(
        url: 'https://fixture.invalid',
        publishableKey: 'fixture',
        authOptions: const FlutterAuthClientOptions(
            autoRefreshToken: false,
            detectSessionInUri: false,
            localStorage: EmptyLocalStorage()),
        httpClient: MockClient((request) {
          requests.add(request.url.path);
          if (request.url.path == '/auth/v1/logout') {
            return Future.value(http.Response('{}', 200));
          }
          return contextLoad.future;
        }));
  });
  setUp(() async {
    contextLoad = Completer<http.Response>();
    requests = [];
    FlutterSecureStorage.setMockInitialValues({});
    const userId = '00000000-0000-4000-8000-000000000001';
    final token =
        '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
          'sub': userId
        })))}.signature';
    await Supabase.instance.client.auth.recoverSession(jsonEncode({
      'access_token': token,
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': userId,
        'aud': 'authenticated',
        'role': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'
      }
    }));
  });
  tearDown(() async {
    if (!contextLoad.isCompleted) {
      contextLoad.complete(http.Response('{}', 200));
    }
  });
  tearDownAll(() async => Supabase.instance.dispose());
  testWidgetsWithEnvironment(() => _environment,
      'restored web session never renders the sign-in form while admin context loads',
      (tester) async {
    await _environment.pumpWidget(tester, const MaterialApp(home: LoginPage()));
    expect(find.text(UserStrings.signIn), findsNothing,
        reason:
            'a restored SDK session must not flash the signed-out login UI');
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
        requests.where((path) => path.startsWith('/auth/v1/token')), isEmpty);
    await _environment.pumpWidget(tester, const SizedBox());
    contextLoad.complete(http.Response('{}', 200));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(seconds: 16));
  });
  testWidgetsWithEnvironment(
      () => _environment, 'signed-out visitors can still open the sign-in form',
      (tester) async {
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await _environment.pumpWidget(tester, const MaterialApp(home: LoginPage()));
    await tester.pump();
    expect(find.text(UserStrings.signIn), findsWidgets);
    expect(find.byType(TextFormField), findsWidgets);
    await _environment.pumpWidget(tester, const SizedBox());
    contextLoad.complete(http.Response('{}', 200));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(seconds: 16));
  });
  testWidgetsWithEnvironment(() => _environment,
      'stalled authenticated navigation offers retry without showing login',
      (tester) async {
    await _environment.pumpWidget(tester, const MaterialApp(home: LoginPage()));
    await tester.pump(const Duration(seconds: 16));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(CommonStrings.retry), findsOneWidget);
    expect(find.text(UserStrings.signIn), findsNothing);
    expect(Supabase.instance.client.auth.currentSession, isNotNull);
    await _environment.pumpWidget(tester, const SizedBox());
    contextLoad.complete(http.Response('{}', 200));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump(const Duration(seconds: 16));
  });
}
