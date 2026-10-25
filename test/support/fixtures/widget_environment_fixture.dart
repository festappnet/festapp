import 'package:material_ui/material_ui.dart' show GlobalMaterialLocalizations;
import 'dart:async';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

/// One explicit locale/catalog environment, loaded through the public widget
/// API. Each tester owns and disposes its root; incompatible fallback/locale
/// environments remain separate processes rather than resetting SDK internals.
class WidgetEnvironmentFixture {
  WidgetEnvironmentFixture(
      {required this.locale, required Map<String, dynamic> translations})
      : _loader = _TranslationsAssetLoader(jsonEncode(translations));
  final Locale locale;
  final _TranslationsAssetLoader _loader;
  final _ready = UniqueKey();

  static void register() {
    TestWidgetsFlutterBinding.ensureInitialized();
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
  }

  Future<void> pumpWidget(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(EasyLocalization(
        key: ValueKey(this),
        supportedLocales: [locale],
        startLocale: locale,
        fallbackLocale: locale,
        saveLocale: false,
        path: 'fixture',
        assetLoader: _loader,
        child: Builder(
            builder: (context) => Localizations(
                locale: context.locale,
                delegates: [
                  ...context.localizationDelegates,
                  ...GlobalMaterialLocalizations.delegates
                ],
                child: KeyedSubtree(key: _ready, child: child)))));
    // Wait only for localization, never for an intentionally pending save/load
    // or an animation in the actual widget under test.
    for (var i = 0; i < 10 && find.byKey(_ready).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    if (find.byKey(_ready).evaluate().isEmpty) {
      throw StateError('Fixture translations did not load');
    }
  }
}

class _TranslationsAssetLoader extends AssetLoader {
  _TranslationsAssetLoader(this.encoded);
  final String encoded;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(encoded) as Map<String, dynamic>;
}

void testWidgetsWithEnvironment(WidgetEnvironmentFixture Function() environment,
    String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    // Load before constructing widgets that evaluate translated labels in their
    // constructor arguments. Subsequent pumps keep this same public root.
    final fixture = environment();
    await fixture.pumpWidget(tester, const SizedBox.shrink());
    // Match App.build locale selection without leaking global Intl state.
    await Intl.withLocale(fixture.locale.toString(), () => body(tester));
  });
}

void testWithWidgetEnvironment(WidgetEnvironmentFixture Function() environment,
    String description, FutureOr<void> Function() body) {
  testWidgetsWithEnvironment(environment, description, (tester) async {
    await tester.runAsync(() async {
      await body();
    });
  });
}
