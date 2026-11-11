import 'dart:convert';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:fstapp/widgets/synced_adaptive_theme.dart';
import 'package:fstapp/services/theme_preference/theme_preference_store.dart';

class _BrowserPreference implements ThemePreferenceStore {
  _BrowserPreference(this.value, {this.legacy, this.enabled = true});
  String? value, legacy;
  @override
  final bool enabled;
  VoidCallback? changed;
  int writes = 0;
  @override
  String? read() => value;
  @override
  String? readLegacy() => legacy;
  @override
  void write(String mode) {
    if (value != mode) {
      value = mode;
      writes++;
    }
  }

  @override
  VoidCallback listen(VoidCallback listener) {
    changed = listener;
    return () => changed = null;
  }

  void publicSelection(String? mode) {
    value = mode;
    changed?.call();
  }
}

Widget _app(_BrowserPreference store) => SyncedAdaptiveTheme(
  store: store,
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
            Text('brightness:${Theme.of(context).brightness.name}'),
            for (final mode in AdaptiveThemeMode.values)
              TextButton(
                onPressed: () => AdaptiveTheme.of(context).setThemeMode(mode),
                child: Text('set:${mode.name}'),
              ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          AdaptiveTheme.prefKey: jsonEncode({
            'theme_mode': 1,
            'default_theme_mode': 0,
          }),
        });
  });
  testWidgets(
    'shared choice beats stale admin cache and syncs both ways without echo',
    (tester) async {
      final store = _BrowserPreference('light');
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text('mode:light'), findsOneWidget);
      expect(find.text('brightness:light'), findsOneWidget);
      store.publicSelection('dark');
      await tester.pumpAndSettle();
      expect(find.text('mode:dark'), findsOneWidget);
      expect(find.text('brightness:dark'), findsOneWidget);
      expect(store.writes, 0);
      await tester.tap(find.text('set:light'));
      await tester.pumpAndSettle();
      expect(store.value, 'light');
      expect(store.writes, 1);
      await tester.tap(find.text('set:system'));
      await tester.pumpAndSettle();
      expect(store.value, 'auto');
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(find.text('brightness:dark'), findsOneWidget);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      store.publicSelection('light');
      await tester.pumpAndSettle();
      expect(find.text('brightness:light'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(store.changed, isNull);
    },
  );
  testWidgets(
    'old admin choice migrates once while canonical auto wins on reopening',
    (tester) async {
      final store = _BrowserPreference(null, legacy: 'dark');
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(store.value, 'dark');
      expect(find.text('mode:dark'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.value = 'auto';
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text('mode:system'), findsOneWidget);
      expect(store.value, 'auto');
    },
  );
  testWidgets(
    'native app keeps AdaptiveTheme persistence and never writes browser preference',
    (tester) async {
      final store = _BrowserPreference(null, enabled: false);
      await tester.pumpWidget(_app(store));
      await tester.pumpAndSettle();
      expect(find.text('mode:dark'), findsOneWidget);
      expect(store.writes, 0);
      expect(store.changed, isNull);
    },
  );
}
