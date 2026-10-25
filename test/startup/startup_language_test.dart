import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/startup/startup_failure_screen.dart';
import 'package:fstapp/startup/startup_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final saved in ['cs', 'en', 'sk', 'de', 'pl', 'uk']) {
    testWidgets('startup failure honors saved $saved while device is English', (
      tester,
    ) async {
      tester.binding.platformDispatcher.localeTestValue = const Locale('en');
      addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);
      SharedPreferences.setMockInitialValues({'locale': saved});
      final language = await resolveStartupLanguage(defaultLanguage: 'cs');
      expect(language, saved);
      await tester.pumpWidget(
        MaterialApp(builder: DependencyMaterialBridge.builder,
          home: StartupFailureScreen(
            phase: 'S05',
            language: language,
            storageOpenFailed: true,
            onRetry: () {},
          ),
        ),
      );
      final labels = {
        'cs': 'Zavřete ostatní karty Festapp',
        'en': 'Close other Festapp tabs',
        'sk': 'Zavrite ostatné karty Festapp',
        'de': 'Schließen Sie andere Festapp-Tabs',
        'pl': 'Zamknij inne karty Festapp',
        'uk': 'Закрийте інші вкладки Festapp',
      };
      expect(find.textContaining(labels[saved]!), findsOneWidget);
    });
  }

  test('no saved language uses the configured app default', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await resolveStartupLanguage(), 'cs');
    expect(await resolveStartupLanguage(defaultLanguage: 'sk'), 'sk');
  });

  test('regional saved locale is normalized', () async {
    SharedPreferences.setMockInitialValues({'locale': 'cs_CZ'});
    expect(await resolveStartupLanguage(defaultLanguage: 'en'), 'cs');
  });

  test('invalid saved locale uses the app default', () async {
    SharedPreferences.setMockInitialValues({'locale': 'invalid'});
    expect(await resolveStartupLanguage(defaultLanguage: 'cs'), 'cs');
  });

  test(
    'blocked or failed preferences cannot hold up the failure surface',
    () async {
      expect(
        await resolveStartupLanguage(
          readSavedLanguage: () => Completer<String?>().future,
          defaultLanguage: 'cs',
          timeout: const Duration(milliseconds: 10),
        ),
        'cs',
      );
      expect(
        await resolveStartupLanguage(
          readSavedLanguage: () async =>
              throw StateError('preferences unavailable'),
          defaultLanguage: 'cs',
        ),
        'cs',
      );
    },
  );
}
