// Explicit browser target, alongside theme_preference_store_browser_cases.dart.
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
// The real browser platform implementation used by EasyLocalization.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;
import 'package:fstapp/services/locale_preference/locale_preference_web.dart';
import 'package:fstapp/startup/startup_language.dart';
import 'package:fstapp/widgets/synced_locale.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

class _Catalog extends AssetLoader {
  const _Catalog();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'label': locale.languageCode,
  };
}

Widget _app() => EasyLocalization(
  supportedLocales: const [Locale('cs'), Locale('en')],
  startLocale: const Locale('cs'),
  fallbackLocale: const Locale('cs'),
  path: 'fixture',
  assetLoader: const _Catalog(),
  child: SyncedLocale(
    child: Builder(
      builder: (context) => MaterialApp(
        builder: DependencyMaterialBridge.builder,
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: [
          ...context.localizationDelegates,
          ...GlobalMaterialLocalizations.delegates,
        ],
        home: Scaffold(
          body: Column(
            children: [
              Text('locale:${context.locale.languageCode}'),
              TextButton(
                onPressed: () => context.setLocale(const Locale('cs')),
                child: const Text('admin Czech'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  SharedPreferencesPlugin.registerWith(null);
  setUp(() {
    SharedPreferences.resetStatic();
    web.window.localStorage.removeItem('flutter.locale');
    web.window.localStorage.removeItem('locale');
  });
  tearDown(() {
    web.window.localStorage.removeItem('flutter.locale');
    web.window.localStorage.removeItem('locale');
  });

  testWidgets(
    'public language initializes Flutter, changes live, and Flutter publishes back',
    (tester) async {
      web.window.localStorage.setItem('flutter.locale', jsonEncode('en'));
      await prepareSharedLocale();
      await EasyLocalization.ensureInitialized();
      expect(await resolveStartupLanguage(), 'en');
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      expect(find.text('locale:en'), findsOneWidget);
      await tester.tap(find.text('admin Czech'));
      await tester.pumpAndSettle();
      expect(
        jsonDecode(web.window.localStorage.getItem('flutter.locale')!),
        'cs',
      );

      web.window.localStorage.setItem('flutter.locale', jsonEncode('en'));
      web.window.dispatchEvent(
        web.StorageEvent(
          'storage',
          web.StorageEventInit(key: 'flutter.locale'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('locale:en'), findsOneWidget);
      web.window.localStorage.setItem('flutter.locale', jsonEncode('cs'));
      web.window.dispatchEvent(web.Event('focus'));
      await tester.pumpAndSettle();
      expect(find.text('locale:cs'), findsOneWidget);
      web.window.localStorage.setItem('flutter.locale', jsonEncode('xx'));
      web.window.dispatchEvent(web.Event('pageshow'));
      await tester.pumpAndSettle();
      expect(find.text('locale:cs'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  test('legacy public preference migrates into actual SharedPreferences before startup', () async {
    web.window.localStorage.setItem('locale', 'en');
    await prepareSharedLocale();
    expect((await SharedPreferences.getInstance()).getString('locale'), 'en');
    expect(
      jsonDecode(web.window.localStorage.getItem('flutter.locale')!),
      'en',
    );
    final store = createLocalePreferenceStore();
    var changes = 0;
    final cancel = store.listen(() => changes++);
    web.window.dispatchEvent(
      web.StorageEvent('storage', web.StorageEventInit(key: 'other')),
    );
    web.window.dispatchEvent(
      web.StorageEvent('storage', web.StorageEventInit(key: 'flutter.locale')),
    );
    expect(changes, 1);
    cancel();
    web.window.dispatchEvent(web.Event('focus'));
    expect(changes, 1);
  });
}
