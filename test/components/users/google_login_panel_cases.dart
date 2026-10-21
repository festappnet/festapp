import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/users/widgets/google_login_panel.dart';
import 'package:fstapp/services/google_auth_service.dart';
import 'package:fstapp/theme_config.dart';

class _Translations extends AssetLoader {
  _Translations(this.catalogs);
  final Map<String, String> catalogs;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(catalogs[locale.languageCode]!) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await font.load();
  });
  test(
      'callback origin and return paths reject cross-origin and encoded routing',
      () {
    for (final path in [
      '//evil.invalid',
      '/%2f%2fevil.invalid',
      '/a/../b',
      '/a?secret=x'
    ]) {
      expect(GoogleAuthService.safeReturnPath(path), '/');
    }
    expect(GoogleAuthService.safeReturnPath('/r48vetrkovice2026'),
        '/r48vetrkovice2026');
    expect(
        GoogleAuthService.captureCallback(
            Uri.parse('https://evil.invalid/app/google-auth?google_code=x')),
        isFalse);
  });
  testWidgets(
      'actual Google panel remains usable at all target widths, themes, locales and continuation states',
      (tester) async {
    final export = Platform.environment['FESTAPP_EXPORT_GOOGLE_VISUALS'] == '1';
    final evidenceRoot = Platform.environment['FESTAPP_GOOGLE_AUTH_EVIDENCE_DIR'] ??
        '.codex-artifacts/google-auth/run';
    final output = Directory('$evidenceRoot/implementation');
    if (export) output.createSync(recursive: true);
    final translations = _Translations({
      for (final language in ['cs', 'en'])
        language: File('assets/translations/$language.json').readAsStringSync(),
    });
    final states = <String, GoogleLoginState>{
      'login': const GoogleLoginState(GoogleLoginStatus.idle),
      'proof': const GoogleLoginState(GoogleLoginStatus.needsAccountProof,
          result: {
            'status': 'needs_account_proof',
            'email': 'jana@example.com'
          }),
      'unlink': const GoogleLoginState(GoogleLoginStatus.needsAccountProof,
          result: {
            'status': 'needs_account_proof',
            'email': 'jana@example.com',
            'intent': 'unlink'
          }),
      'profile':
          const GoogleLoginState(GoogleLoginStatus.needsProfile, result: {
        'status': 'needs_profile',
        'name': 'Jana Nováková',
        'email': 'jana@example.com',
        'mailboxRequired': false
      }),
      'mailbox':
          const GoogleLoginState(GoogleLoginStatus.needsProfile, result: {
        'status': 'needs_profile',
        'name': 'Jana Nováková',
        'email': 'jana@example.com',
        'mailboxRequired': true
      }),
      'mfa': const GoogleLoginState(GoogleLoginStatus.needsMfa,
          result: {'status': 'needs_mfa'}),
      'loading': const GoogleLoginState(GoogleLoginStatus.completing),
      'authenticated': const GoogleLoginState(GoogleLoginStatus.authenticated),
      'error': const GoogleLoginState(GoogleLoginStatus.retryableError,
          error: 'attempt_expired'),
      'cancelled': const GoogleLoginState(GoogleLoginStatus.cancelled,
          error: 'provider_cancelled'),
    };
    for (final width in [360, 390, 768, 1440]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width.toDouble(), 1000);
      for (final language in ['cs', 'en']) {
        for (final dark in [false, true]) {
          final theme = dark
              ? ThemeConfig.theme(brightness: Brightness.dark)
              : ThemeConfig.theme();
          // Retain only locale/theme infrastructure. Removing home disposes the
          // previous panel before global login state is reset for a fresh case.
          Future<void> pumpEnvironment(Widget child) =>
              tester.pumpWidget(EasyLocalization(
                key: ValueKey(language),
                supportedLocales: const [Locale('cs'), Locale('en')],
                startLocale: Locale(language),
                saveLocale: false,
                path: 'assets/translations',
                assetLoader: translations,
                child: Builder(
                    builder: (context) => MaterialApp(
                          locale: context.locale,
                          supportedLocales: context.supportedLocales,
                          localizationsDelegates: context.localizationDelegates,
                          theme: theme,
                          home: child,
                        )),
              ));
          for (final entry in states.entries) {
            await pumpEnvironment(const SizedBox.shrink());
            GoogleAuthService.state.value = entry.key == 'proof'
                ? entry.value
                : const GoogleLoginState(GoogleLoginStatus.idle);
            final boundary = GlobalKey();
            final navigation = Completer<void>();
            GoogleAuthService.navigationClaimed = false;
            final panel = GoogleLoginPanel(
                capability: () async => true,
                onAuthenticated: () => navigation.future);
            final content = RepaintBoundary(
                key: boundary,
                child: Scaffold(
                    body: SafeArea(
                        child: SingleChildScrollView(
                            child: Center(
                                child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 500),
                                    child: panel))))));
            await pumpEnvironment(content);
            await tester.pumpAndSettle();
            final panelContext = tester.element(find.byType(GoogleLoginPanel));
            expect(panelContext.locale, Locale(language));
            expect(Theme.of(panelContext).brightness,
                dark ? Brightness.dark : Brightness.light);
            GoogleAuthService.state.value = entry.value;
            await tester.pump();
            if (export) {
              // Give engine-side image decoding time before reference captures.
              await tester.runAsync(() async {
                await Future<void>.delayed(const Duration(milliseconds: 50));
              });
            }
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull,
                reason: '$width $language $dark ${entry.key}');
            if (entry.key == 'login') {
              expect(find.byType(GoogleLoginPanel), findsOneWidget,
                  reason: '$width $language $dark login panel');
              expect(find.byType(OutlinedButton), findsOneWidget,
                  reason:
                      '$width $language $dark state=${GoogleAuthService.state.value.status}');
            }
            if (entry.key == 'proof') {
              final fields =
                  tester.widgetList<TextField>(find.byType(TextField));
              expect(fields.first.controller!.text, 'jana@example.com');
              fields.first.controller!.text = 'chosen@example.com';
              GoogleAuthService.state.value = GoogleLoginState(
                  GoogleLoginStatus.completing,
                  result: entry.value.result);
              GoogleAuthService.state.value = entry.value;
              await tester.pump();
              expect(fields.first.controller!.text, 'chosen@example.com');
            }
            if (entry.key == 'authenticated') {
              expect(GoogleAuthService.isContinuation, isTrue);
              expect(find.byType(CircularProgressIndicator), findsOneWidget);
              expect(find.byType(OutlinedButton), findsNothing);
            }
            if (entry.key == 'authenticated') {
              navigation.complete();
              await tester.pump();
              expect(
                  GoogleAuthService.state.value.status, GoogleLoginStatus.idle);
              expect(GoogleAuthService.isContinuation, isFalse);
            }
            if (export) {
              await tester.runAsync(() async {
                final image = await (boundary.currentContext!.findRenderObject()
                        as RenderRepaintBoundary)
                    .toImage();
                final bytes =
                    await image.toByteData(format: ui.ImageByteFormat.png);
                await File(
                        '${output.path}/flutter-${entry.key}-$language-${dark ? 'dark' : 'light'}-$width.png')
                    .writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    GoogleAuthService.state.value =
        const GoogleLoginState(GoogleLoginStatus.idle);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
