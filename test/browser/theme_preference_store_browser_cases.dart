// Explicit browser target: fvm flutter test --platform chrome --concurrency=1
// test/browser/browser_preference_store_test.dart
import 'dart:convert';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/synced_adaptive_theme.dart';

import 'package:flutter_test/flutter_test.dart';
// Register the real platform implementation already supplied by shared_preferences.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:web/web.dart' as web;
import 'package:fstapp/services/theme_preference/theme_preference_web.dart';

void main() {
  setUpAll(() => SharedPreferencesPlugin.registerWith(null));
  const legacyKeys = [
    'adaptive_theme_preferences',
    'flutter.adaptive_theme_preferences',
  ];
  setUp(() {
    for (final key in ['theme', ...legacyKeys]) {
      web.window.localStorage.removeItem(key);
    }
  });
  tearDown(() {
    for (final key in ['theme', ...legacyKeys]) {
      web.window.localStorage.removeItem(key);
    }
  });
  test('actual browser store reads both admin formats and shares explicit system mode', () {
    final store = createThemePreferenceStore();
    for (final key in legacyKeys) {
      web.window.localStorage.setItem(
        key,
        jsonEncode(jsonEncode({'theme_mode': 0})),
      );
      expect(store.readLegacy(), 'light');
      web.window.localStorage.removeItem(key);
    }
    store.write('auto');
    expect(web.window.localStorage.getItem('theme'), 'auto');
    web.window.localStorage.setItem('theme', 'dark');
    expect(store.read(), 'dark');
  });
  test(
    'browser events refresh active tabs and dispose removes subscriptions',
    () {
      final store = createThemePreferenceStore();
      var changes = 0;
      final dispose = store.listen(() => changes++);
      web.window.dispatchEvent(
        web.StorageEvent('storage', web.StorageEventInit(key: 'other')),
      );
      expect(changes, 0);
      web.window.dispatchEvent(
        web.StorageEvent('storage', web.StorageEventInit(key: 'theme')),
      );
      web.window.dispatchEvent(web.Event('focus'));
      web.window.dispatchEvent(web.Event('pageshow'));
      expect(changes, 3);
      dispose();
      web.window.dispatchEvent(
        web.StorageEvent('storage', web.StorageEventInit(key: 'theme')),
      );
      expect(changes, 3);
    },
  );
  testWidgets(
    'real admin theme uses public preference and publishes admin changes',
    (tester) async {
      web.window.localStorage.setItem('theme', 'light');
      web.window.localStorage.setItem(
        'adaptive_theme_preferences',
        jsonEncode(jsonEncode({'theme_mode': 1})),
      );
      await tester.pumpWidget(
        SyncedAdaptiveTheme(
          initial: AdaptiveThemeMode.light,
          light: ThemeData.light(),
          dark: ThemeData.dark(),
          builder: (light, dark) => MaterialApp(
            theme: light,
            darkTheme: dark,
            home: Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: [
                    Text('mode:${AdaptiveTheme.of(context).mode.name}'),
                    TextButton(
                      onPressed: () => AdaptiveTheme.of(context).setLight(),
                      child: const Text('admin light'),
                    ),
                    TextButton(
                      onPressed: () => AdaptiveTheme.of(context).setSystem(),
                      child: const Text('admin auto'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('mode:light'), findsOneWidget);
      web.window.localStorage.setItem('theme', 'dark');
      web.window.dispatchEvent(
        web.StorageEvent('storage', web.StorageEventInit(key: 'theme')),
      );
      await tester.pumpAndSettle();
      expect(find.text('mode:dark'), findsOneWidget);
      await tester.tap(find.text('admin light'));
      await tester.pumpAndSettle();
      expect(web.window.localStorage.getItem('theme'), 'light');
      await tester.tap(find.text('admin auto'));
      await tester.pumpAndSettle();
      expect(web.window.localStorage.getItem('theme'), 'auto');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
