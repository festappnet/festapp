import 'dart:ui' as ui;

import 'package:fstapp/components/unit/views/unit_meta_capi_settings.dart';
import 'package:fstapp/components/unit/meta_capi_strings.dart';

import 'dart:async';

import 'package:fstapp/components/unit/views/unit_website_consent_settings.dart';
import 'package:fstapp/components/unit/unit_website_consent.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/unit/views/unit_measurement_settings.dart';
import 'package:fstapp/components/unit/views/unit_measurement_help.dart';
import 'package:fstapp/components/unit/unit_measurement_approval.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

Future<void> settleConsent(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final edit = find.byWidgetPredicate(
    (w) =>
        w is TextButton &&
        w.child is Text &&
        (w.child as Text).data == CommonStrings.edit,
  );
  final platform = find.byType(DropdownButtonFormField<String>);
  if (edit.evaluate().isNotEmpty && platform.evaluate().isEmpty) {
    await tester.ensureVisible(edit.first);
    await tester.tap(edit.first);
    await tester.pumpAndSettle();
  }
}

Future<void> openPolicy(WidgetTester tester) async {
  if (find
      .widgetWithText(TextField, FormStrings.cmsPolicyId)
      .evaluate()
      .isEmpty) {
    await tester.ensureVisible(find.text(FormStrings.cmsPolicyManual));
    await tester.tap(find.text(FormStrings.cmsPolicyManual));
    await tester.pumpAndSettle();
  }
}

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets('Meta CAPI is hidden without organizer permission', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UnitMetaCapiSettings(
            unitId: 1,
            load: (_) async => throw const PostgrestException(
              message: 'access denied',
              code: '42501',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text(MetaCapiStrings.loadFailed), findsNothing);
    expect(find.text(CommonStrings.retry), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    // Unexpected load failure remains retryable; a known denial above stays hidden.
    var attempts = 0;
    final retry = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitMetaCapiSettings(
              unitId: 1,
              load: (_) {
                attempts++;
                if (attempts == 1) return Future.error(StateError('offline'));
                return retry.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(MetaCapiStrings.loadFailed).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.retry));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    retry.complete({'allowed': true, 'websites': [], 'forms': []});
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text(MetaCapiStrings.noWebsites), findsOneWidget);
    expect(find.text(MetaCapiStrings.noForms), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, CommonStrings.save),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('Meta CAPI clears the write-only token after saving', (
    tester,
  ) async {
    const toastChannel = MethodChannel('PonnamKarthik/fluttertoast');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      toastChannel,
      (_) async => true,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        toastChannel,
        null,
      ),
    );
    for (final scenario in [
      'first token',
      'replacement',
      'stored token',
      'save disabled',
      'token failure',
    ]) {
      var saved = scenario == 'replacement' || scenario == 'stored token';
      var enabled = false;
      String? revision = saved ? 'revision' : null;
      final operations = <String>[];
      var formUpdates = 0;
      final tokenWrite = Completer<void>();
      final hasDraft = scenario != 'stored token';
      final enable = scenario != 'save disabled';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitMetaCapiSettings(
                key: ValueKey(scenario),
                unitId: 1,
                load: (_) async => {
                  'allowed': true,
                  'revision': revision,
                  'token_saved': saved,
                  'enabled': enabled,
                  'dataset': '123456',
                  'websites': [
                    'https://tickets.example',
                    'https://organizer.example',
                  ],
                  'website_origin': 'https://tickets.example',
                  'forms': [
                    {
                      'id': 10,
                      'title': 'Concert tickets',
                      'enabled': formUpdates > 0,
                    },
                  ],
                },
                mutate: (operation, params) async {
                  expect(params['p_unit'], 1);
                  if (operation == 'set_form_meta_purchase') {
                    expect(params['p_form'], 10);
                    expect(params['p_enabled'], true);
                    formUpdates++;
                    return;
                  }
                  operations.add(operation);
                  expect(operation, 'save_unit_meta_purchase');
                  expect(
                    params['p_dataset'],
                    scenario == 'replacement' ? '987654' : '123456',
                  );
                  expect(
                    params['p_website_origin'],
                    scenario == 'replacement'
                        ? 'https://organizer.example'
                        : 'https://tickets.example',
                  );
                  if (hasDraft) {
                    expect(params['p_token'], 'secret-token-value');
                    await tokenWrite.future;
                    saved = true;
                  } else {
                    expect(params.containsKey('p_token'), isFalse);
                  }
                  expect(params['p_enabled'], enable);
                  enabled = params['p_enabled'] == true;
                  revision = 'revision';
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(MetaCapiStrings.title));
      await tester.pumpAndSettle();
      final enabledSwitch = find.widgetWithText(
        SwitchListTile,
        MetaCapiStrings.enabled,
      );
      expect(
        tester.widget<SwitchListTile>(enabledSwitch).onChanged == null,
        !saved,
      );
      final token = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      expect(tester.widget<TextField>(token).decoration?.counterText, '');
      expect(tester.widget<TextField>(token).maxLength, 4096);
      final testCode = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText == MetaCapiStrings.testCode,
      );
      expect(tester.widget<TextField>(testCode).decoration?.counterText, '');
      expect(tester.widget<TextField>(testCode).maxLength, 60);
      if (hasDraft) {
        await tester.ensureVisible(token);
        await tester.enterText(token, 'secret-token-value');
        await tester.pumpAndSettle();
      }
      expect(tester.widget<SwitchListTile>(enabledSwitch).onChanged, isNotNull);
      if (enable) {
        await tester.ensureVisible(enabledSwitch);
        await tester.tap(enabledSwitch);
        await tester.pumpAndSettle();
      }
      if (scenario == 'replacement') {
        final dataset = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == MetaCapiStrings.dataset,
        );
        await tester.ensureVisible(dataset);
        await tester.enterText(dataset, '987654');
        await tester.enterText(testCode, 'TEST42');
        final website = find.byType(DropdownButtonFormField<String>);
        await tester.ensureVisible(website);
        await tester.tap(website);
        await tester.pumpAndSettle();
        await tester.tap(find.text('https://organizer.example').last);
        await tester.pumpAndSettle();
        final formSwitch = find.widgetWithText(
          SwitchListTile,
          'Concert tickets',
        );
        await tester.ensureVisible(formSwitch);
        await tester.tap(formSwitch);
        await tester.pumpAndSettle();
        expect(formUpdates, 1);
        expect(tester.widget<TextField>(dataset).controller!.text, '987654');
        expect(tester.widget<TextField>(testCode).controller!.text, 'TEST42');
        expect(
          tester.widget<TextField>(token).controller!.text,
          'secret-token-value',
        );
        expect(tester.widget<SwitchListTile>(enabledSwitch).value, isTrue);
        expect(find.text('https://organizer.example'), findsOneWidget);
        expect(tester.widget<SwitchListTile>(formSwitch).value, isTrue);
      }
      final save = find.widgetWithText(FilledButton, CommonStrings.save);
      expect(save, findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, CommonStrings.save),
        findsNothing,
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      if (hasDraft) {
        expect(operations, ['save_unit_meta_purchase']);
        expect(enabled, isFalse);
        expect(tester.widget<SwitchListTile>(enabledSwitch).onChanged, isNull);
        if (scenario == 'token failure') {
          tokenWrite.completeError(StateError('Token could not be saved'));
        } else {
          tokenWrite.complete();
        }
      }
      await tester.pumpAndSettle();
      expect(operations, ['save_unit_meta_purchase']);
      expect(enabled, enable && scenario != 'token failure');
      expect(saved, scenario != 'token failure');
      expect(tester.widget<TextField>(token).controller!.text, isEmpty);
      expect(find.text('secret-token-value'), findsNothing);
      expect(
        tester.widget<TextField>(token).decoration!.helperText,
        saved ? MetaCapiStrings.saved : null,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      // Let the failure toast's display timer finish before the next scenario.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
    }
  });

  testWidgets('Meta CAPI refreshes after saving the first website', (
    tester,
  ) async {
    var websites = <String>[];
    Widget settings() => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: UnitMetaCapiSettings(
            unitId: 1,
            savedWebsites: websites,
            load: (_) async => {'allowed': true, 'websites': websites},
          ),
        ),
      ),
    );
    await tester.pumpWidget(settings());
    await tester.pumpAndSettle();
    await tester.tap(find.text(MetaCapiStrings.title));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, CommonStrings.save);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    websites = ['https://tickets.example'];
    await tester.pumpWidget(settings());
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(find.text(MetaCapiStrings.noWebsites), findsNothing);
  });

  testWidgets('Meta CAPI shows terminal counts and reasons without retry', (
    tester,
  ) async {
    final fixture = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    for (final code in [
      'connector_changed',
      'consent_invalid',
      'order_ineligible',
      'payment_too_old',
      'attempts_exhausted',
      'retention_expired',
    ]) {
      await fixture.pumpWidget(
        tester,
        MaterialApp(
          key: ValueKey(code),
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitMetaCapiSettings(
                unitId: 1,
                load: (_) async => {
                  'allowed': true,
                  'websites': [],
                  'forms': [],
                  'queue': {'invalid': 3, 'expired': 2},
                  'last_error': {
                    'code': code,
                    'status': code == 'retention_expired'
                        ? 'expired'
                        : 'invalid',
                  },
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(MetaCapiStrings.title));
      await tester.pumpAndSettle();
      expect(find.text('${MetaCapiStrings.invalidCount}: 3'), findsOneWidget);
      expect(find.text('${MetaCapiStrings.expired}: 2'), findsOneWidget);
      expect(find.text(MetaCapiStrings.outcomeReason(code)), findsOneWidget);
      expect(find.text(MetaCapiStrings.retry), findsNothing);
    }
    // A sent test event outside an open Test Events session explains why it is missing there.
    await fixture.pumpWidget(
      tester,
      MaterialApp(
        key: const ValueKey('test_events_inactive'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitMetaCapiSettings(
              unitId: 1,
              load: (_) async => {
                'allowed': true,
                'websites': [],
                'forms': [],
                'queue': {'sent': 1},
                'last_error': {
                  'code': 'test_events_inactive',
                  'status': 'sent',
                },
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(MetaCapiStrings.title));
    await tester.pumpAndSettle();
    expect(find.text(MetaCapiStrings.testEventsInactive), findsOneWidget);
    expect(find.text(MetaCapiStrings.deliveryFailed), findsNothing);
  });

  testWidgets('Meta CAPI identifies the saved token by its masked suffix', (
    tester,
  ) async {
    await initializeDateFormatting('cs');
    final fixture = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    for (final hinted in [true, false]) {
      await fixture.pumpWidget(
        tester,
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitMetaCapiSettings(
                key: ValueKey(hinted),
                unitId: 1,
                load: (_) async => {
                  'allowed': true,
                  'token_saved': true,
                  'dataset': '123456',
                  'websites': ['https://tickets.example'],
                  'website_origin': 'https://tickets.example',
                  'token_changed_at': '2026-11-21T12:00:00Z',
                  if (hinted) 'token_hint': 'a1B2c3D4e5',
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(MetaCapiStrings.title));
      await tester.pumpAndSettle();
      final token = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText,
      );
      final helper = tester.widget<TextField>(token).decoration!.helperText;
      if (hinted) {
        final date = DateFormat.yMd('cs')
            .format(DateTime.parse('2026-11-21T12:00:00Z').toLocal());
        expect(helper, MetaCapiStrings.savedHint('a1B2c3D4e5', date));
        expect(helper, startsWith('Uložený token …a1B2c3D4e5 · uložen $date'));
      } else {
        // Connectors saved before hints existed keep the generic text.
        expect(helper, MetaCapiStrings.saved);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
  testWidgets('Meta CAPI pause asks to replace the token', (tester) async {
    await initializeDateFormatting('cs');
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en_US';
    addTearDown(() => Intl.defaultLocale = previousLocale);
    final fixture = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    await fixture.pumpWidget(
      tester,
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitMetaCapiSettings(
              unitId: 1,
              load: (_) async => {
                'allowed': true,
                'paused_at': '2026-11-19T10:00:00Z',
                'last_error': {
                  'code': 'credentials',
                  'at': '2026-11-19T10:00:00Z',
                },
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(MetaCapiStrings.title));
    await tester.pumpAndSettle();
    expect(find.text(MetaCapiStrings.paused), findsOneWidget);
    final warning = tester.widget<Icon>(
      find.byIcon(Icons.warning_amber_rounded),
    );
    final context = tester.element(find.byType(UnitMetaCapiSettings));
    expect(warning.color, ThemeConfig.warningColor(context));
    final statusText = tester.widget<Text>(find.text(MetaCapiStrings.paused));
    final foreground = statusText.style!.color!;
    final background = Theme.of(context).colorScheme.surface;
    final light = foreground.computeLuminance() > background.computeLuminance()
        ? foreground
        : background;
    final dark = foreground.computeLuminance() > background.computeLuminance()
        ? background
        : foreground;
    expect(
      (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05),
      greaterThanOrEqualTo(4.5),
    );
    final date = DateFormat.yMd('cs')
        .add_jm()
        .format(DateTime.parse('2026-11-19T10:00:00Z').toLocal());
    expect(find.text('${MetaCapiStrings.credentials} · $date'), findsOneWidget);
  });

  setUpAll(() async {
    if (Platform.environment.containsKey('MEASUREMENT_REVIEW_ARTIFACT_DIR')) {
      final loader = FontLoader('Futura');
      for (final font in [
        'fonts/Futura PT Book.ttf',
        'fonts/Futura PT Medium.ttf',
        'fonts/Gill Sans Bold.otf',
      ]) {
        loader.addFont(rootBundle.load(font));
      }
      await loader.load();
    }
  });
  test(
    'measurement help links target published pages and existing anchors',
    () {
      const root = 'automation/release/help';
      for (final (language, site, basics) in [
        (
          'cs',
          'https://vstupenky.online',
          'https://vstupenky.online/napoveda/mereni-formularu/#zapnuti',
        ),
        (
          'en',
          'https://festapp.net',
          'https://festapp.net/help/form-measurement/#enable',
        ),
      ]) {
        expect(
          UnitMeasurementHelp.basics
              .url(site: site, publishedLanguage: language)
              .toString(),
          basics,
        );
        final isCzech = language == 'cs';
        final manifest = isCzech ? 'pages.json' : 'pages.en.json';
        final pages =
            jsonDecode(File('$root/$manifest').readAsStringSync()) as List;
        final slugs = pages.map((page) => page['slug']).toSet();
        for (final topic in UnitMeasurementHelp.values) {
          final url = topic.url(site: site, publishedLanguage: language)!;
          expect(url.pathSegments.first, isCzech ? 'napoveda' : 'help');
          final slug = url.pathSegments[1];
          expect(slugs, contains(slug), reason: '$language: $url');
          final html = File('$root/${isCzech ? '' : 'en/'}$slug.html')
              .readAsStringSync();
          expect(url.fragment, isNotEmpty);
          expect(
            html,
            contains('id="${url.fragment}"'),
            reason: '$language: $url',
          );
        }
      }
      expect(UnitMeasurementHelp.basics.url(publishedLanguage: 'de'), isNull);
      expect(
        UnitMeasurementHelp.basics.url(
          site: 'https://tenant.example',
          publishedLanguage: null,
        ),
        isNull,
      );
    },
  );

  for (final operation in ['confirmation', 'disable']) {
    testWidgets(
      'CMS ignores $operation response after removing the last website',
      (tester) async {
        const site = 'https://culture.example';
        var websites = [site];
        var saved = true;
        var calls = 0;
        final result = Completer<UnitWebsiteConsent>();
        final binding = {
          'id': 'culture',
          'websiteOrigin': site,
          'platform': 'html',
          'version': 7,
          'state': operation == 'confirmation' ? 'draft' : 'ready',
          'providerConfig': {'provider': 'cookiebot'},
        };
        UnitWebsiteConsent data(String state, int version) =>
            UnitWebsiteConsent.fromJson({
              'consentRevision': 'a' * 32,
              'bindings': [
                {...binding, 'state': state, 'version': version},
              ],
            });
        Future<void> pump() => tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Scaffold(
              body: SingleChildScrollView(
                child: UnitWebsiteConsentSettings(
                  unitId: 2,
                  websites: websites,
                  saved: saved,
                  load: () async => data(binding['state']! as String, 7),
                  save: (origin, platform, config, version, revision, confirm) {
                    expect(origin, site);
                    expect(revision, 'a' * 32);
                    expect(version, 7);
                    expect(confirm, isTrue);
                    calls++;
                    return result.future;
                  },
                  disable: (id, version) {
                    expect(id, 'culture');
                    expect(version, 7);
                    calls++;
                    return result.future;
                  },
                ),
              ),
            ),
          ),
        );
        await pump();
        await settleConsent(tester);
        final action = find.text(
          operation == 'confirmation'
              ? FormStrings.cmsConfirm
              : FormStrings.cmsDisable,
        );
        if (operation == 'confirmation') {
          await tester.ensureVisible(find.byType(Checkbox));
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pump();
        expect(calls, 1);
        websites = [];
        saved = false;
        await pump();
        result.complete(
          data(operation == 'confirmation' ? 'ready' : 'disabled', 8),
        );
        await tester.pumpAndSettle();
        expect(find.byType(Card), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('CMS copies another website without replacing the open draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const sites = ['https://culture.example', 'https://concert.example'];
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitWebsiteConsentSettings(
              unitId: 2,
              websites: sites,
              saved: true,
              load: () async => UnitWebsiteConsent.fromJson({
                'consentRevision': 'a' * 32,
                'bindings': [
                  {
                    'id': 'first',
                    'websiteOrigin': sites[0],
                    'platform': 'html',
                    'version': 3,
                    'state': 'ready',
                    'providerConfig': {'provider': 'cookieconsent'},
                  },
                  {
                    'id': 'second',
                    'websiteOrigin': sites[1],
                    'platform': 'joomla',
                    'version': 9,
                    'state': 'ready',
                    'providerConfig': {'provider': 'cookiebot'},
                  },
                ],
              }),
              export: (id, version) async {
                expect(id, 'second');
                expect(version, 9);
                return {'website': 'concert.example'};
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final hiddenEditor = tester.element(
      find.byKey(
        const ValueKey('https://culture.example'),
        skipOffstage: false,
      ),
    );
    for (var index = 0; index < 8; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      var focusedInEditor = false;
      FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
        ancestor,
      ) {
        focusedInEditor = ancestor == hiddenEditor;
        return !focusedInEditor;
      });
      expect(focusedInEditor, isFalse);
    }
    await settleConsent(tester);
    await tester.tap(find.text(FormStrings.cmsAdvancedCategories));
    await tester.pumpAndSettle();
    final category = find.widgetWithText(
      TextField,
      FormStrings.cmsAnalyticsCategory,
    );
    await tester.enterText(category, 'my-draft');
    await tester.pumpAndSettle();
    await tester.tap(find.text(FormStrings.cmsCopyFor('Joomla')));
    await tester.pumpAndSettle();
    expect(clipboard, contains('concert.example'));
    expect(tester.widget<TextField>(category).controller!.text, 'my-draft');
    expect(find.text(FormStrings.cmsConfirm), findsOneWidget);
    final details = find.text(FormStrings.cmsShowConfiguration);
    final exportCard = find.ancestor(of: details, matching: find.byType(Card));
    expect(
      find.descendant(of: exportCard, matching: find.text('concert.example')),
      findsOneWidget,
    );
    final editOther = find.descendant(
      of: exportCard.first,
      matching: find.widgetWithText(TextButton, CommonStrings.edit),
    );
    await tester.tap(editOther);
    await tester.pumpAndSettle();
    await tester.tap(find.text(CommonStrings.keepEditing));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(category).controller!.text, 'my-draft');

    await tester.tap(editOther);
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, CommonStrings.discardChanges),
    );
    await tester.pumpAndSettle();
    expect(category, findsNothing);
  });

  Future<void> pumpConsent(
    WidgetTester tester, {
    Future<String> Function(String)? detect,
    List<Map<String, dynamic>> bindings = const [],
    Future<UnitWebsiteConsent> Function(
      String,
      String,
      Map<String, dynamic>,
      int,
      String,
      bool,
    )?
    save,
    Future<UnitWebsiteConsent> Function(String, String, String, int, String)?
    confirmDetected,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
        body: SingleChildScrollView(
          child: UnitWebsiteConsentSettings(
            unitId: 2,
            websites: const ['https://poradatel.cz'],
            saved: true,
            load: () async => UnitWebsiteConsent.fromJson({
              'consentRevision': 'a' * 32,
              'bindings': bindings,
            }),
            detectPolicy:
                detect ?? (_) async => throw StateError("fixture unavailable"),
            save: save,
            confirmDetected: confirmDetected,
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'Complianz failed automatic detection leaves manual draft editable',
    (tester) async {
      Map<String, dynamic>? draft;
      await pumpConsent(
        tester,
        detect: (_) async => throw StateError('website unavailable'),
        save: (_, _, config, _, _, confirm) async {
          expect(confirm, false);
          draft = config;
          return UnitWebsiteConsent.fromJson({
            'consentRevision': 'a' * 32,
            'bindings': [],
          });
        },
      );
      await tester.pumpAndSettle();
      await settleConsent(tester);
      expect(find.text(CommonStrings.loading), findsNothing);
      await openPolicy(tester);
      await settleConsent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '42',
      );
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsSaveDraft));
      await tester.tap(find.text(FormStrings.cmsSaveDraft));
      await settleConsent(tester);
      expect(draft, {'provider': 'complianz', 'policyId': '42'});
    },
  );

  testWidgets(
    'Complianz pending probe does not block changing provider and ignores late result',
    (tester) async {
      final pending = Completer<String>();
      await pumpConsent(tester, detect: (_) => pending.future);
      await settleConsent(tester);
      final selectors = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(selectors.every((selector) => selector.onChanged != null), true);
      // Drive the same callback used by keyboard and dropdown selection.
      selectors.last.onChanged!('cookiebot');
      await settleConsent(tester);
      expect(find.text(CommonStrings.loading), findsNothing);
      pending.complete('42');
      await settleConsent(tester);
      expect(
        find.text(
          '${FormStrings.cmsPolicyNumber('42')} · ${FormStrings.cmsPolicyFromWebsite}',
        ),
        findsNothing,
      );
      expect(find.text(FormStrings.cmsFreshChoiceHelp), findsOneWidget);
    },
  );

  testWidgets(
    'Complianz failed reload preserves saved draft and manual changes',
    (tester) async {
      await pumpConsent(
        tester,
        detect: (_) async => throw StateError('blocked'),
        bindings: [
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'websiteOrigin': 'https://poradatel.cz',
            'platform': 'wordpress',
            'version': 1,
            'state': 'draft',
            'providerConfig': {'provider': 'complianz', 'policyId': '41'},
          },
        ],
      );
      await settleConsent(tester);
      expect(find.text('${FormStrings.cmsPolicySaved}: 41'), findsOneWidget);
      await openPolicy(tester);
      await settleConsent(tester);
      final field = find.widgetWithText(TextField, FormStrings.cmsPolicyId);
      expect(tester.widget<TextField>(field).controller!.text, '41');
      await tester.enterText(field, '43');
      await tester.ensureVisible(find.text(FormStrings.cmsPolicyReload));
      await tester.tap(find.text(FormStrings.cmsPolicyReload));
      await settleConsent(tester);
      expect(tester.widget<TextField>(field).controller!.text, '43');
    },
  );

  testWidgets(
    'Complianz changed-policy conflict reloads and requires fresh confirmation',
    (tester) async {
      var probes = 0;
      var confirmations = 0;
      await pumpConsent(
        tester,
        detect: (_) async => ++probes == 1 ? '42' : '43',
        save: (_, _, _, _, _, _) async =>
            throw StateError('detected confirmation must use probe'),
        confirmDetected: (_, _, policy, _, _) async {
          confirmations++;
          if (confirmations == 1) {
            expect(policy, '42');
            throw const ComplianzPolicyChanged();
          }
          expect(policy, '43');
          return UnitWebsiteConsent.fromJson({
            'consentRevision': 'a' * 32,
            'bindings': [],
          });
        },
      );
      await settleConsent(tester);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsConfirm));
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsPolicyChanged), findsOneWidget);
      expect(
        find.text(
          '${FormStrings.cmsPolicyNumber('43')} · ${FormStrings.cmsPolicyFromWebsite}',
        ),
        findsOneWidget,
      );
      expect(find.text(FormStrings.cmsUnavailable), findsNothing);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsConfirm));
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await settleConsent(tester);
      expect(confirmations, 2);
      expect(
        probes,
        2,
        reason: 'successful confirmation must not immediately probe again',
      );
    },
  );

  testWidgets(
    'Complianz conflict recovery releases busy state after stalled probe deadline',
    (tester) async {
      var attempts = 0;
      final pending = Completer<String>();
      await pumpConsent(
        tester,
        detect: (_) => ++attempts == 1 ? Future.value('42') : pending.future,
        confirmDetected: (_, _, _, _, _) async =>
            throw const ComplianzPolicyChanged(),
      );
      await settleConsent(tester);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsConfirm));
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await settleConsent(tester);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text(FormStrings.cmsPolicyDetectionFailed), findsOneWidget);
      expect(
        tester
            .widgetList<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .every((selector) => selector.onChanged != null),
        true,
      );
      await tester.ensureVisible(find.text(FormStrings.cmsPolicyManual));
      await openPolicy(tester);
      await settleConsent(tester);
      final field = find.widgetWithText(TextField, FormStrings.cmsPolicyId);
      expect(tester.widget<TextField>(field).enabled, true);
      expect(tester.widget<TextField>(field).controller!.text, '42');
      pending.complete('43');
      await settleConsent(tester);
      expect(tester.widget<TextField>(field).controller!.text, '42');
    },
  );

  testWidgets(
    'Complianz probes saved websites without approval and ignores unsaved results',
    (tester) async {
      const site = 'https://poradatel.cz';
      var saved = false;
      var attempts = 0;
      final pending = Completer<String>();
      Future<void> pump() => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitWebsiteConsentSettings(
                key: const ValueKey('eligibility'),
                unitId: 2,
                websites: const [site],

                saved: saved,
                load: () async => UnitWebsiteConsent.fromJson({
                  'consentRevision': 'a' * 32,
                  'bindings': [],
                }),
                detectPolicy: (_) {
                  attempts++;
                  return pending.future;
                },
              ),
            ),
          ),
        ),
      );
      await pump();
      await tester.pumpAndSettle();
      expect(attempts, 0, reason: 'unsaved websites cannot start a probe');
      saved = true;
      await pump();
      await settleConsent(tester);
      expect(
        attempts,
        1,
        reason: 'saved website needs neither platform approval nor existing binding',
      );
      expect(find.text(CommonStrings.loading), findsOneWidget);
      saved = false;
      await pump();
      await settleConsent(tester);
      expect(find.text(CommonStrings.loading), findsNothing);
      pending.complete('42');
      await settleConsent(tester);
      expect(
        find.text(
          '${FormStrings.cmsPolicyNumber('42')} · ${FormStrings.cmsPolicyFromWebsite}',
        ),
        findsNothing,
      );
      expect(attempts, 1);
    },
  );

  testWidgets(
    'Complianz stalled probe settles, times out to manual entry and ignores late success',
    (tester) async {
      final pending = Completer<String>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitWebsiteConsentSettings(
                unitId: 2,
                websites: const ['https://poradatel.cz'],

                saved: true,
                load: () async => UnitWebsiteConsent.fromJson({
                  'consentRevision': 'a' * 32,
                  'bindings': [],
                }),
                detectPolicy: (_) => pending.future,
              ),
            ),
          ),
        ),
      );
      await settleConsent(tester);
      expect(find.text(CommonStrings.loading), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsPolicyDetectionFailed), findsOneWidget);
      expect(find.text(CommonStrings.loading), findsNothing);
      pending.complete('42');
      await settleConsent(tester);
      expect(
        find.text(
          '${FormStrings.cmsPolicyNumber('42')} · ${FormStrings.cmsPolicyFromWebsite}',
        ),
        findsNothing,
      );
      await openPolicy(tester);
      await settleConsent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '43',
      );
      await settleConsent(tester);
      expect(find.widgetWithText(TextField, '43'), findsOneWidget);
    },
  );

  testWidgets('Complianz detects read-only ID, reloads and offers manual fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var attempts = 0;
    Map<String, dynamic>? pinned;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: UnitWebsiteConsentSettings(
              unitId: 2,
              websites: const ['https://poradatel.cz'],

              saved: true,
              load: () async => UnitWebsiteConsent.fromJson({
                'consentRevision': 'a' * 32,
                'bindings': [],
              }),
              detectPolicy: (_) async {
                attempts++;
                if (attempts == 3) throw StateError('blocked');
                return attempts == 1 ? '42' : '43';
              },
              save: (_, _, config, _, _, _) async {
                pinned = config;
                return UnitWebsiteConsent.fromJson({
                  'consentRevision': 'a' * 32,
                  'bindings': [],
                });
              },
            ),
          ),
        ),
      ),
    );
    await settleConsent(tester);
    expect(
      find.text(
        '${FormStrings.cmsPolicyNumber('42')} · ${FormStrings.cmsPolicyFromWebsite}',
      ),
      findsOneWidget,
    );
    final policyLine = find.text(
      '${FormStrings.cmsPolicyNumber('42')} · ${FormStrings.cmsPolicyFromWebsite}',
    );
    final reloadRow = find
        .ancestor(of: policyLine, matching: find.byType(Wrap))
        .first;
    expect(
      find.descendant(
        of: reloadRow,
        matching: find.text(FormStrings.cmsPolicyReload),
      ),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(Checkbox));
    await settleConsent(tester);
    await tester.tap(find.text(FormStrings.cmsPolicyReload));
    await settleConsent(tester);
    expect(
      find.text(
        '${FormStrings.cmsPolicyNumber('43')} · ${FormStrings.cmsPolicyFromWebsite}',
      ),
      findsOneWidget,
    );
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
    await tester.tap(find.text(FormStrings.cmsPolicyReload));
    await settleConsent(tester);
    expect(find.text(FormStrings.cmsPolicyDetectionFailed), findsOneWidget);
    expect(
      find.widgetWithText(TextField, FormStrings.cmsPolicyId),
      findsNothing,
    );
    await openPolicy(tester);
    await settleConsent(tester);
    await tester.enterText(
      find.widgetWithText(TextField, FormStrings.cmsPolicyId),
      '44',
    );
    await tester.tap(find.byType(Checkbox));
    await settleConsent(tester);
    await tester.tap(find.text(FormStrings.cmsConfirm));
    await settleConsent(tester);
    expect(pinned, {'provider': 'complianz', 'policyId': '44'});
  });
  testWidgets(
    'CMS confirmation requires saved settings and explicit coverage; export and disable use stored binding',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const site = 'https://poradatel.cz';
      var saved = false;
      var version = 0;
      var state = 'draft';
      var confirmations = 0;
      UnitWebsiteConsent data() => UnitWebsiteConsent.fromJson({
        'consentRevision': 'a' * 32,
        'bindings': version == 0
            ? []
            : [
                {
                  'id': '11111111-1111-1111-1111-111111111111',
                  'websiteOrigin': site,
                  'platform': 'wordpress',
                  'version': version,
                  'state': state,
                  'providerConfig': {'provider': 'complianz', 'policyId': '42'},
                },
              ],
      });
      final fixture = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ),
      );
      Future<void> pump() => fixture.pumpWidget(
        tester,
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitWebsiteConsentSettings(
                detectPolicy: (_) async => throw StateError('blocked'),
                key: ValueKey('consent-$state'),
                unitId: 2,
                websites: const [site],

                saved: saved,
                load: () async => data(),
                save:
                    (
                      origin,
                      platform,
                      config,
                      expected,
                      revision,
                      confirm,
                    ) async {
                      expect(origin, site);
                      expect(expected, version);
                      expect(revision, 'a' * 32);
                      expect(config, {
                        'provider': 'complianz',
                        'policyId': '42',
                      });
                      if (confirm) confirmations++;
                      version++;
                      state = confirm ? 'ready' : 'draft';
                      return data();
                    },
                export: (id, v) async {
                  expect(v, version);
                  return {
                    'schemaVersion': 1,
                    'binding': {'id': id, 'version': v},
                  };
                },
                disable: (id, v) async {
                  expect(v, version);
                  version++;
                  state = 'disabled';
                  return data();
                },
              ),
            ),
          ),
        ),
      );
      await pump();
      await settleConsent(tester);
      FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
      );
      expect(confirm().onPressed, isNull);
      expect(
        find.text(FormStrings.measurementWebsitesSaveFirst),
        findsOneWidget,
      );
      saved = true;
      await pump();
      await settleConsent(tester);
      expect(confirm().onPressed, isNull);
      await openPolicy(tester);
      await settleConsent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        'invalid',
      );
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsPolicyIdInvalid), findsOneWidget);
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '42',
      );
      await tester.tap(find.byType(Checkbox));
      await settleConsent(tester);
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await settleConsent(tester);
      expect(confirmations, 1);
      expect(find.text(FormStrings.cmsState("ready")), findsOneWidget);
      expect(find.widgetWithText(TextButton, CommonStrings.edit), findsNothing);
      final footer = find
          .ancestor(
            of: find.text(CommonStrings.close),
            matching: find.byType(Wrap),
          )
          .first;
      expect(
        find.descendant(
          of: footer,
          matching: find.text(FormStrings.cmsDisable),
        ),
        findsOneWidget,
      );
      final card = find.ancestor(of: footer, matching: find.byType(Card)).first;
      expect(
        tester.getTopLeft(find.text(FormStrings.cmsDisable)).dx,
        closeTo(tester.getTopLeft(card).dx + 16, 0.1),
      );
      await tester.tap(find.text(CommonStrings.close));
      await tester.pumpAndSettle();
      final edit = find.widgetWithText(TextButton, CommonStrings.edit);
      expect(tester.widget<TextButton>(edit).focusNode!.hasFocus, isTrue);
      final retained = find.byType(ExcludeFocus, skipOffstage: false);
      expect(
        tester.widgetList<ExcludeFocus>(retained).any((item) => item.excluding),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused?.findAncestorWidgetOfExactType<ExcludeFocus>()?.excluding,
        isNot(true),
      );
      final headerActions = find
          .ancestor(of: edit, matching: find.byType(Wrap))
          .first;
      expect(
        find.descendant(
          of: headerActions,
          matching: find.text(FormStrings.cmsCopyFor('WordPress')),
        ),
        findsOneWidget,
      );
      final copyAction = find.widgetWithText(
        FilledButton,
        FormStrings.cmsCopyFor('WordPress'),
      );
      final hint = find.text(
        FormStrings.cmsInstallHint(FormStrings.cmsInstallField('wordpress')),
      );
      final ready = find.widgetWithText(Chip, FormStrings.cmsState('ready'));
      final website = find.text('poradatel.cz');
      final summary = find.textContaining('WordPress · Complianz');
      expect(
        tester.getRect(summary).top - tester.getRect(website).bottom,
        closeTo(8, 0.1),
      );
      expect(
        tester.getRect(copyAction).top - tester.getRect(ready).bottom,
        greaterThanOrEqualTo(16),
      );
      expect(
        tester.getRect(copyAction).center.dy,
        closeTo(tester.getRect(edit).center.dy, 0.1),
      );
      expect(
        tester.getRect(hint).top - tester.getRect(copyAction).bottom,
        closeTo(12, 0.1),
      );
      final closedCard = find.ancestor(
        of: copyAction,
        matching: find.byType(Card),
      );
      expect(
        tester.getRect(closedCard).bottom - tester.getRect(hint).bottom,
        closeTo(16, 0.1),
      );
      await tester.tap(edit);
      await settleConsent(tester);

      expect(version, 1);
      expect(find.text(FormStrings.cmsConfirm), findsNothing);
      expect(find.text(FormStrings.cmsSaveDraft), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text(FormStrings.cmsCopyFor('WordPress')));
      await settleConsent(tester);
      expect(copied, contains('"schemaVersion": 1'));
      expect(find.text(CommonStrings.copiedToClipboard), findsOneWidget);
      final firstStep = find.textContaining('1. ');
      final secondStep = find.textContaining('2. ');
      expect(firstStep, findsOneWidget);
      expect(
        tester.getRect(firstStep).top - tester.getRect(copyAction).bottom,
        closeTo(12, 0.1),
      );
      expect(
        tester.getRect(secondStep).top - tester.getRect(firstStep).bottom,
        closeTo(8, 0.1),
      );
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.text(FormStrings.cmsShowConfiguration));
      await settleConsent(tester);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(version, 1, reason: 'copying never reconfirms coverage');
      await tester.tap(find.text('Complianz'));
      await settleConsent(tester);
      await tester.tap(find.text('Cookiebot').last);
      await settleConsent(tester);
      expect(find.byType(SelectableText), findsNothing);
      expect(confirm().onPressed, isNull);
      expect(find.text(FormStrings.cmsCopyFor('WordPress')), findsNothing);
      expect(find.text(FormStrings.cmsSaveDraft), findsNothing);
      expect(find.text(FormStrings.cmsChangesPending), findsOneWidget);
      await tester.tap(find.text(CommonStrings.discardChanges));
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsCopyFor('WordPress')), findsOneWidget);
      expect(find.text(FormStrings.cmsConfirm), findsNothing);
      expect(
        version,
        1,
        reason: 'discarding edits preserves the active binding',
      );
      for (final suspendedState in ['confirmation_required', 'unavailable']) {
        state = suspendedState;
        await pump();
        await settleConsent(tester);
        await openPolicy(tester);
        await settleConsent(tester);
        await tester.enterText(
          find.widgetWithText(TextField, FormStrings.cmsPolicyId),
          '43',
        );
        await settleConsent(tester);
        expect(
          find.text(FormStrings.cmsSaveDraft),
          findsNothing,
          reason: 'a temporarily unavailable confirmed binding cannot become a draft by accident',
        );
        await tester.tap(find.text(CommonStrings.discardChanges));
        await settleConsent(tester);
        expect(version, 1);
        expect(confirmations, 1);
      }
      state = 'ready';
      await pump();
      await settleConsent(tester);
      await tester.tap(find.text(FormStrings.cmsDisable));
      await settleConsent(tester);
      expect(state, 'disabled');
      expect(version, 2);
    },
  );

  testWidgets(
    'CMS provider fields, pending server state and draft changes fail closed',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<UnitWebsiteConsent>();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitWebsiteConsentSettings(
                detectPolicy: (_) async => throw StateError('blocked'),
                unitId: 2,
                websites: const ['https://poradatel.cz'],

                saved: true,
                load: () => pending.future,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      pending.complete(
        UnitWebsiteConsent.fromJson({
          'consentRevision': 'a' * 32,
          'bindings': [],
        }),
      );
      await settleConsent(tester);
      await tester.tap(find.text('Complianz'));
      await settleConsent(tester);
      await tester.tap(find.text('CookieConsent v3').last);
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsAdvancedCategories), findsOneWidget);
      expect(find.text(FormStrings.cmsAnalyticsCategory), findsNothing);
      await tester.tap(find.text(FormStrings.cmsAdvancedCategories));
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsAnalyticsCategory), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsAnalyticsCategory),
        'marketing',
      );
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsCategoriesInvalid), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await settleConsent(tester);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('CookieConsent v3'));
      await settleConsent(tester);
      await tester.tap(find.text('Cookiebot').last);
      await settleConsent(tester);
      expect(find.text('Cookiebot CBID'), findsNothing);
      expect(find.text(FormStrings.cmsAnalyticsCategory), findsNothing);
      await tester.tap(find.text('WordPress'));
      await settleConsent(tester);
      await tester.tap(find.text('Wix').last);
      await settleConsent(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Wix').first,
      );
      await settleConsent(tester);
      await tester.tap(find.text('WordPress').last);
      await settleConsent(tester);
      expect(find.text('Complianz'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'CMS stale confirmation and unavailable server block export until explicit reload',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitWebsiteConsentSettings(
                detectPolicy: (_) async => throw StateError('blocked'),
                unitId: 2,
                websites: const ['https://poradatel.cz'],

                saved: true,
                load: () async {
                  loads++;
                  return UnitWebsiteConsent.fromJson({
                    'consentRevision': 'a' * 32,
                    'bindings': [],
                  });
                },
                save: (_, _, _, _, _, _) async =>
                    throw StateError('website_consent_conflict'),
              ),
            ),
          ),
        ),
      );
      await settleConsent(tester);
      await openPolicy(tester);
      await settleConsent(tester);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '42',
      );
      await tester.tap(find.byType(Checkbox));
      await settleConsent(tester);
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await settleConsent(tester);
      expect(find.text(FormStrings.cmsUnavailable), findsWidgets);
      expect(find.byType(SelectableText), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
            )
            .onPressed,
        isNull,
      );
      expect(loads, 1);
      await tester.tap(find.text(CommonStrings.retry));
      await settleConsent(tester);
      expect(loads, 2);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
            )
            .onPressed,
        isNull,
        reason: 'reloading cannot confirm coverage',
      );
    },
  );

  testWidgets(
    'CMS website selection follows added, saved and removed origins',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var sites = <String>[];
      var saved = true;
      var loads = 0;
      Future<void> pump() => tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitWebsiteConsentSettings(
                detectPolicy: (_) async => throw StateError('blocked'),
                key: const ValueKey('same-unit'),
                unitId: 2,
                websites: sites,

                saved: saved,
                load: () async {
                  loads++;
                  return UnitWebsiteConsent.fromJson({
                    'consentRevision': 'a' * 32,
                    'bindings': [],
                  });
                },
              ),
            ),
          ),
        ),
      );
      await pump();
      await settleConsent(tester);
      expect(find.byType(CheckboxListTile), findsNothing);
      sites = ['https://poradatel.cz', 'https://tanec.cz'];
      saved = false;
      await pump();
      await settleConsent(tester);
      expect(find.text('poradatel.cz'), findsOneWidget);
      saved = true;
      await pump();
      await settleConsent(tester);
      expect(loads, 2, reason: 'canonical save reloads current semantic scope');
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNotNull,
      );
      sites = ['https://tanec.cz'];
      saved = false;
      await pump();
      await settleConsent(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('tanec.cz'), findsOneWidget);
      saved = true;
      await pump();
      await settleConsent(tester);
      expect(loads, 3);
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets(
    'CMS export text renders inside persisted measurement expansion state',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard_unavailable');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ExpansionTile(
                key: const PageStorageKey('measurement-expansion'),
                title: const Text('Measurement settings'),
                maintainState: true,
                children: [
                  UnitWebsiteConsentSettings(
                    detectPolicy: (_) async => throw StateError('blocked'),
                    unitId: 2,
                    websites: const ['https://poradatel.cz'],

                    saved: true,
                    load: () async => UnitWebsiteConsent.fromJson({
                      'consentRevision': 'a' * 32,
                      'bindings': [
                        {
                          'id': '11111111-1111-1111-1111-111111111111',
                          'version': 1,
                          'websiteOrigin': 'https://poradatel.cz',
                          'platform': 'wordpress',
                          'state': 'ready',
                          'providerConfig': {
                            'provider': 'complianz',
                            'policyId': '42',
                          },
                        },
                      ],
                    }),
                    export: (id, version) async => {
                      'schemaVersion': 1,
                      'binding': {'id': id, 'version': version},
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await settleConsent(tester);
      await tester.tap(find.text('Measurement settings'));
      await settleConsent(tester);
      final exportButton = find.widgetWithText(
        FilledButton,
        FormStrings.cmsCopyFor('WordPress'),
      );
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final manualTitle = find.text(CommonStrings.copyManually);
      expect(manualTitle, findsOneWidget);
      final manualField = find.byType(TextField);
      expect(
        tester.widget<TextField>(manualField).controller!.text,
        contains('"schemaVersion": 1'),
      );
      Navigator.of(tester.element(manualTitle)).pop();
      await tester.pumpAndSettle();
      final measurement = find.text('Measurement settings');
      await tester.tap(measurement);
      await tester.pumpAndSettle();
      await tester.tap(measurement);
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsShowConfiguration));
      await settleConsent(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        contains('"schemaVersion": 1'),
      );
    },
  );

  for (final state in [
    'draft',
    'unrequested',
    'requested',
    'retry',
    'unavailable',
    'approved',
    'running',
    'invalid',
    'removed',
    'desktop',
    'large text',
  ]) {
    testWidgets('saved website UX independent of runtime approval: $state', (
      tester,
    ) async {
      tester.view.physicalSize = Size(state == 'desktop' ? 1000 : 412, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controllers = List.generate(6, (_) => TextEditingController());
      for (final controller in controllers) {
        addTearDown(controller.dispose);
      }
      final host = state == 'large text'
          ? '${'a' * 63}.obecni-kultura.example'
          : 'poradatel.cz';
      final site = 'https://$host';
      controllers[0].text = state == 'removed' ? '' : site;
      if (state == 'running') {
        controllers[1].text = 'GTM-ABCD';
        controllers[3].text = 'https://poradatel.cz/privacy';
      }
      final known = state != 'unavailable';
      final saved = state == 'draft' ? <String>[] : [site];
      final status = UnitMeasurementApproval.fromJson({
        'approved': true,
        'organization_allowed': true,
        'runtime_supported': true,
        if (known)
          'request_state': state == 'retry'
              ? 'retry_available'
              : state == 'requested'
              ? 'requested'
              : 'not_requested',
        'can_request': !['approved', 'requested', 'running'].contains(state),
        'saved_origins': saved,
        'approved_origins': ['approved', 'running'].contains(state)
            ? [site]
            : <String>[],
        'requested_origins': state == 'requested' || state == 'retry'
            ? [site]
            : <String>[],
        'requested_at': state == 'requested' || state == 'retry'
            ? '2026-11-11T10:00:00Z'
            : null,
      });
      var requests = 0;
      final boundary = GlobalKey();
      final fixture = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      await fixture.pumpWidget(
        tester,
        MaterialApp(
          theme: ThemeConfig.theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(state == 'large text' ? 2 : 1),
            ),
            child: child!,
          ),
          locale: const Locale('cs'),
          supportedLocales: const [Locale('cs')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    child: UnitMeasurementSettings(
                      websitesController: controllers[0],
                      savedWebsites: saved,
                      gtmController: controllers[1],
                      scriptsController: controllers[2],
                      privacyUrlController: controllers[3],
                      consentTitleController: controllers[4],
                      consentTextController: controllers[5],
                      enabled: true,
                      consentLayout: 'bar',
                      canEdit: true,
                      approval: status,
                      onEnabledChanged: (_) {},
                      onConsentLayoutChanged: (_) {},
                      onRequestApproval: () => requests++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (state != 'removed') {
        final address = find.text(host);
        final row = find
            .ancestor(of: address, matching: find.byType(Row))
            .first;
        final chip = find.descendant(of: row, matching: find.byType(Chip));
        final remove = find.descendant(
          of: row,
          matching: find.byTooltip(FormStrings.measurementRemoveWebsite(site)),
        );
        final addressRect = tester.getRect(address);
        final removeRect = tester.getRect(remove);
        expect(addressRect.right, lessThanOrEqualTo(removeRect.left));
        expect(tester.getSize(remove).shortestSide, greaterThanOrEqualTo(48));
        expect(
          find.descendant(of: row, matching: find.byType(IconButton)),
          findsOneWidget,
        );
        if (state == 'draft') {
          expect(chip, findsOneWidget);
          expect(find.text(FormStrings.measurementUnsavedHelp), findsOneWidget);
        } else {
          expect(chip, findsNothing);
          expect(addressRect.center.dy, closeTo(removeRect.center.dy, 0.1));
        }
        if (state == 'large text') {
          expect(addressRect.height, greaterThan(48));
        }
      }
      if (state == 'invalid') {
        await tester.enterText(
          find.widgetWithText(TextFormField, FormStrings.measurementAddWebsite),
          '$site/vstupenky',
        );
        await tester.ensureVisible(
          find.widgetWithText(OutlinedButton, CommonStrings.add),
        );
        await tester.tap(
          find.widgetWithText(OutlinedButton, CommonStrings.add),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(FormStrings.measurementWebsitesInvalid),
          findsOneWidget,
        );
      }
      if (state == 'running') {
        expect(find.text(FormStrings.measurementOn), findsOneWidget);
        expect(find.text(FormStrings.measurementPolicySummary), findsOneWidget);
        expect(find.text('GTM'), findsOneWidget);
        expect(find.byType(Chip), findsNWidgets(3));
      }
      final button = find.widgetWithText(
        OutlinedButton,
        FormStrings.measurementApprovalRequest,
      );
      expect(
        button,
        findsNothing,
        reason: 'saved websites need no platform review',
      );
      expect(requests, 0);
      expect(
        find.text(FormStrings.measurementWebsiteDraft),
        state == 'draft' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(FormStrings.measurementApprovalRequired),
        findsNothing,
        reason: 'Adding an origin must not revoke overall Unit approval',
      );
      expect(find.text(FormStrings.measurementWebsitesSaveFirst), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      if (Platform.environment['MEASUREMENT_REVIEW_ARTIFACT_DIR']
          case final String directory) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(directory).createSync(recursive: true);
          File('$directory/fixed-$state.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final canEdit in [true, false]) {
    testWidgets(
      'destinations and consent bridge opt-in when off; canEdit=$canEdit',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fixture = WidgetEnvironmentFixture(
          locale: const Locale('cs'),
          translations: jsonDecode(
            File('assets/translations/cs.json').readAsStringSync(),
          ) as Map<String, dynamic>,
        );
        final websites = TextEditingController(
          text: 'https://approved.example\nhttps://pending.example',
        );
        addTearDown(websites.dispose);
        final gtm = TextEditingController(text: 'GTM-ABCD');
        final privacy = TextEditingController(
          text: 'https://organizer.example/privacy',
        );
        addTearDown(privacy.dispose);
        final scripts = TextEditingController(
          text: '<script>/* saved */</script>',
        );
        addTearDown(gtm.dispose);
        addTearDown(scripts.dispose);
        bool enabled = false;
        bool consentBridge = false;
        String layout = 'bar';
        final consentTitle = TextEditingController();
        final consentText = TextEditingController();
        addTearDown(consentTitle.dispose);
        addTearDown(consentText.dispose);
        await fixture.pumpWidget(
          tester,
          MaterialApp(
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('cs')],
            home: Scaffold(
              body: SingleChildScrollView(
                child: StatefulBuilder(
                  builder: (context, setState) => Form(
                    child: UnitMeasurementSettings(
                      websitesController: websites,
                      savedWebsites: const [
                        "https://approved.example",
                        "https://pending.example",
                      ],
                      approval: const UnitMeasurementApproval(
                        approved: true,
                        organizationAllowed: true,
                        runtimeSupported: true,
                        requestState: MeasurementRequestState.notRequested,
                        canRequest: true,
                        savedOrigins: [
                          'https://approved.example',
                          'https://pending.example',
                        ],
                      ),
                      enabled: enabled,
                      consentBridge: consentBridge,
                      onConsentBridgeChanged: (value) =>
                          setState(() => consentBridge = value),
                      consentLayout: layout,
                      consentTitleController: consentTitle,
                      consentTextController: consentText,
                      onConsentLayoutChanged: (value) =>
                          setState(() => layout = value),
                      canEdit: canEdit,
                      gtmController: gtm,
                      scriptsController: scripts,
                      privacyUrlController: privacy,
                      onEnabledChanged: (value) =>
                          setState(() => enabled = value),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(FormStrings.measurementTitle), findsNothing);
        expect(find.text(FormStrings.gtmContainer), findsOneWidget);
        expect(
          find.widgetWithText(
            SwitchListTile,
            FormStrings.measurementUnitEnabled,
          ),
          findsOneWidget,
        );
        expect(find.text(FormStrings.measurementUnitDisabled), findsOneWidget);
        expect(find.text('approved.example'), findsOneWidget);
        expect(find.text('pending.example'), findsOneWidget);
        expect(find.text(FormStrings.measurementWebsiteDraft), findsNothing);
        expect(
          tester
              .widget<TextFormField>(
                find.widgetWithText(
                  TextFormField,
                  FormStrings.measurementAddWebsite,
                ),
              )
              .enabled,
          canEdit,
        );
        expect(
          UnitMeasurementSettings.validateWebsites(
            'https://example.com\nhttps://www.example.com:443',
          ),
          isNull,
        );
        expect(
          UnitMeasurementSettings.parseWebsites(
            'https://NEW.example:0443\nhttps://new.example',
          ),
          ['https://new.example'],
        );
        for (final invalid in [
          'https://127.1',
          'https://2130706433',
          'https://0x7f000001',
          'https://example.123',
          'http://example.com',
          'https://example.com/',
          'https://example.com/path',
          'https://example.com?x',
          'https://example.com#x',
          'https://user@example.com',
          'https://example.com:65536',
          List.generate(11, (i) => 'https://site$i.example').join('\n'),
        ]) {
          expect(
            UnitMeasurementSettings.validateWebsites(invalid),
            FormStrings.measurementWebsitesInvalid,
          );
        }
        expect(
          tester.getTopLeft(find.text(FormStrings.measurementBasics)).dy,
          lessThan(
            tester.getTopLeft(find.text(FormStrings.measurementWebsites)).dy,
          ),
        );
        expect(
          tester.getTopLeft(find.text(FormStrings.measurementWebsites)).dy,
          lessThan(
            tester
                .getTopLeft(find.text(FormStrings.measurementConsentBridge))
                .dy,
          ),
        );
        if (canEdit) {
          final add = find.widgetWithText(OutlinedButton, CommonStrings.add);
          await tester.ensureVisible(add);
          await tester.enterText(
            find.widgetWithText(
              TextFormField,
              FormStrings.measurementAddWebsite,
            ),
            'https://novy.example',
          );
          await tester.tap(add);
          await tester.pumpAndSettle();
          expect(
            UnitMeasurementSettings.parseWebsites(websites.text),
            contains('https://novy.example'),
          );
          expect(
            find.text(FormStrings.measurementWebsiteDraft),
            findsOneWidget,
          );
          final remove = find.descendant(
            of: find
                .ancestor(
                  of: find.text('novy.example'),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byTooltip(
              FormStrings.measurementRemoveWebsite('https://novy.example'),
            ),
          );
          await tester.ensureVisible(remove);
          await tester.tap(remove);
          await tester.pumpAndSettle();
          expect(
            UnitMeasurementSettings.parseWebsites(websites.text),
            isNot(contains('https://novy.example')),
          );
        }
        final gtmField = find.byWidgetPredicate(
          (widget) => widget is TextFormField && widget.controller == gtm,
        );
        expect(tester.widget<TextFormField>(gtmField).enabled, canEdit);
        final privacyField = find.byWidgetPredicate(
          (widget) => widget is TextFormField && widget.controller == privacy,
        );
        expect(privacyField, findsOneWidget);
        final field = tester.widget<TextFormField>(privacyField);
        expect(field.enabled, canEdit);
        expect(field.validator!('https://organizer.example/privacy'), isNull);
        expect(field.validator!(''), isNull);
        for (final invalid in [
          'javascript:alert(1)',
          'data:text/plain,x',
          'http://example.com',
          '/privacy',
          'https://user:pass@example.com',
          'https://@example.com',
          'https://example.com:99999',
          'https://example.com/${'x' * 2048}',
        ]) {
          expect(
            field.validator!(invalid),
            FormStrings.measurementPrivacyUrlInvalid,
          );
        }
        final bridgeSwitch = find.widgetWithText(
          SwitchListTile,
          FormStrings.measurementConsentBridge,
        );
        if (canEdit) {
          final semantics = tester.ensureSemantics();
          final help = find.byTooltip(
            FormStrings.measurementHelpFor(
              FormStrings.measurementConsentBridge,
            ),
          );
          expect(
            find.descendant(of: bridgeSwitch, matching: help),
            findsNothing,
          );
          final switchNode = tester.getSemantics(bridgeSwitch);
          final helpNode = tester.getSemantics(help);
          expect(switchNode.id, isNot(helpNode.id));
          expect(
            switchNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          expect(
            helpNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
            isTrue,
          );
          semantics.dispose();
        }
        final bridge = tester.widget<SwitchListTile>(bridgeSwitch);
        expect(bridge.value, isFalse);
        expect(bridge.onChanged == null, !canEdit);
        expect(
          find.text(FormStrings.measurementConsentBridgeConfirmation),
          findsNothing,
        );
        if (canEdit) {
          await tester.ensureVisible(bridgeSwitch);
          await tester.tap(bridgeSwitch);
          await tester.pumpAndSettle();
          expect(consentBridge, isFalse);
          expect(
            find.text(FormStrings.measurementConsentBridgeConfirmation),
            findsOneWidget,
          );
          final terms = find.text(
            FormStrings.measurementConsentBridgeConfirmation,
          );
          final dialog = find.byType(AppAlertDialog);
          expect(
            tester.getRect(dialog).contains(tester.getRect(terms).topLeft),
            isTrue,
          );
          expect(
            tester.getRect(terms).right,
            lessThan(tester.getRect(dialog).right),
          );
          final confirm = find.widgetWithText(
            FilledButton,
            CommonStrings.confirm,
          );
          expect(
            tester.getSize(confirm).shortestSide,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(find.text(CommonStrings.cancel));
          await tester.pumpAndSettle();
          expect(consentBridge, isFalse);
          await tester.tap(bridgeSwitch);
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(FilledButton, CommonStrings.confirm),
          );
          await tester.pumpAndSettle();
          expect(consentBridge, isTrue);
          await tester.ensureVisible(
            find.text(FormStrings.measurementShowTerms),
          );
          await tester.tap(find.text(FormStrings.measurementShowTerms));
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(FilledButton, CommonStrings.confirm),
            findsNothing,
          );
          await tester.tap(
            find.widgetWithText(TextButton, CommonStrings.close),
          );
          await tester.pumpAndSettle();
          await tester.tap(bridgeSwitch);
          await tester.pumpAndSettle();
          expect(consentBridge, isFalse);
        }
        await tester.ensureVisible(find.text(FormStrings.measurementOwnBanner));
        await tester.tap(find.text(FormStrings.measurementOwnBanner));
        await tester.pumpAndSettle();
        final enabledSwitch = find.widgetWithText(
          SwitchListTile,
          FormStrings.measurementUnitEnabled,
        );
        expect(
          find.text(FormStrings.measurementConsentLayoutBar),
          findsOneWidget,
          reason: 'bar is the default layout',
        );
        for (final controller in [consentTitle, consentText]) {
          final field = find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField && widget.controller == controller,
          );
          expect(tester.widget<TextFormField>(field).enabled, canEdit);
        }
        expect(
          find.textContaining('FeatureFormSettings.measurementConsentTitle'),
          findsNothing,
        );
        expect(
          find.text(FormStrings.measurementConsentCustomTextHelp),
          findsOneWidget,
        );
        final toggle = tester.widget<SwitchListTile>(enabledSwitch);
        expect(toggle.onChanged == null, !canEdit);
        if (canEdit) {
          final dropdown = find.text(FormStrings.measurementConsentLayoutBar);
          await tester.ensureVisible(dropdown);
          await tester.tap(dropdown);
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(FormStrings.measurementConsentLayoutModal).last,
          );
          await tester.pumpAndSettle();
          expect(layout, 'modal');
          await tester.ensureVisible(enabledSwitch);
          await tester.tap(enabledSwitch);
          await tester.pumpAndSettle();
          expect(enabled, isTrue);
          final enabledPrivacyField = tester.widget<TextFormField>(
            privacyField,
          );
          expect(
            enabledPrivacyField.validator!(''),
            FormStrings.measurementPrivacyUrlRequired,
          );
          expect(
            enabledPrivacyField.validator!('https://organizer.example/privacy'),
            isNull,
          );
          gtm.clear();
          scripts.clear();
          expect(enabledPrivacyField.validator!(''), isNull);
          scripts.text = '<script>/* saved */</script>';
          expect(
            enabledPrivacyField.validator!(''),
            FormStrings.measurementPrivacyUrlRequired,
          );
          gtm.text = 'GTM-ABCD';
          await tester.tap(enabledSwitch);
          await tester.pumpAndSettle();
          expect(enabled, isFalse);
          expect(
            tester.widget<TextFormField>(privacyField).validator!(''),
            isNull,
          );
          expect(gtm.text, 'GTM-ABCD');
          expect(scripts.text, '<script>/* saved */</script>');
        }
        await tester.ensureVisible(find.text(FormStrings.measurementAdvanced));
        await tester.tap(find.text(FormStrings.measurementAdvanced));
        await tester.pumpAndSettle();
        final scriptField = find.byWidgetPredicate(
          (widget) => widget is TextFormField && widget.controller == scripts,
        );
        expect(scriptField, findsOneWidget);
        expect(tester.widget<TextFormField>(scriptField).enabled, canEdit);
        final howItWorks = find.text(FormStrings.measurementHowItWorks);
        await tester.ensureVisible(howItWorks);
        await tester.tap(howItWorks);
        await tester.pumpAndSettle();
        final paragraphs = FormStrings.measurementActivationHelp.split('\n\n');
        expect(paragraphs, hasLength(3));
        final first = tester.getRect(find.text(paragraphs.first));
        final second = tester.getRect(find.text(paragraphs[1]));
        expect(second.left, first.left);
        expect(second.top - first.bottom, closeTo(12, 0.1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final (name, enabled, canEdit, url, warned) in [
    ('missing link', true, true, '', true),
    ('reader without edit access', true, false, '', false),
    ('measurement off', false, true, '', false),
    ('saved link', true, true, 'https://organizer.example/privacy', false),
  ]) {
    testWidgets('collapsed section warning: $name', (tester) async {
      final fixture = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final gtm = TextEditingController(text: 'GTM-ABCD');
      final privacy = TextEditingController(text: url);
      final scripts = TextEditingController();
      final consentTitle = TextEditingController();
      final consentText = TextEditingController();
      addTearDown(consentTitle.dispose);
      addTearDown(consentText.dispose);
      addTearDown(gtm.dispose);
      addTearDown(privacy.dispose);
      addTearDown(scripts.dispose);
      final form = GlobalKey<FormState>();
      await fixture.pumpWidget(
        tester,
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('cs')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: Form(
                key: form,
                child: UnitMeasurementSettings(
                  enabled: enabled,
                  consentLayout: 'bar',
                  consentTitleController: consentTitle,
                  consentTextController: consentText,
                  onConsentLayoutChanged: (_) {},
                  canEdit: canEdit,
                  gtmController: gtm,
                  scriptsController: scripts,
                  privacyUrlController: privacy,
                  onEnabledChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final warning = find.text(FormStrings.measurementNoPrivacyPolicy);
      expect(warning, warned ? findsOneWidget : findsNothing);
      expect(find.text(FormStrings.gtmContainer), findsOneWidget);
      final required = enabled && url.isEmpty;
      expect(form.currentState!.validate(), !required);
      if (warned) {
        gtm.clear();
        await tester.pump();
        expect(warning, findsNothing);
        gtm.text = 'GTM-ABCD';
        await tester.pump();
        expect(warning, findsOneWidget);
        expect(form.currentState!.validate(), isFalse);
        await tester.pump();
        expect(
          find.text(FormStrings.measurementPrivacyUrlRequired),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (name, enabled, canEdit, approved, requested, busy) in [
    ('missing approval', true, true, false, false, false),
    ('sent request', true, true, false, true, false),
    ('approved', true, true, true, false, false),
    ('new website after approval', true, true, true, true, false),
    ('measurement off', false, true, false, false, false),
    ('read only', true, false, false, false, false),
    ('sending request', true, true, false, false, true),
    ('awaiting setup', true, true, false, false, false),
  ]) {
    testWidgets('platform approval: $name', (tester) async {
      final fixture = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
      final controllers = List.generate(6, (_) => TextEditingController());
      for (final controller in controllers) {
        addTearDown(controller.dispose);
      }
      final requestedAt = DateTime.utc(2026, 11, 9, 12);
      var requests = 0;
      await fixture.pumpWidget(
        tester,
        MaterialApp(
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [Locale('cs')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: UnitMeasurementSettings(
                websitesController: name == 'new website after approval'
                    ? (controllers[5]..text = 'https://new.example')
                    : null,
                enabled: enabled,
                consentLayout: 'bar',
                canEdit: canEdit,
                gtmController: controllers[0],
                scriptsController: controllers[1],
                privacyUrlController: controllers[2],
                consentTitleController: controllers[3],
                consentTextController: controllers[4],
                onEnabledChanged: (_) {},
                onConsentLayoutChanged: (_) {},
                requestingApproval: busy,
                approval: UnitMeasurementApproval.fromJson({
                  'approved': approved,
                  'organization_allowed': approved || name == 'awaiting setup',
                  'runtime_supported': approved,
                  'request_state': requested ? 'requested' : 'not_requested',
                  'can_request': !approved && !requested,
                  'saved_origins': name == 'new website after approval'
                      ? ['https://new.example']
                      : <String>[],
                  'requested_at': requested
                      ? requestedAt.toIso8601String()
                      : null,
                }),
                onRequestApproval: () => requests++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
        OutlinedButton,
        FormStrings.measurementApprovalRequest,
      );
      final canRequest = enabled && canEdit && !approved && !requested;
      expect(button, canRequest ? findsOneWidget : findsNothing);
      if (canRequest) {
        expect(tester.widget<OutlinedButton>(button).onPressed != null, !busy);
        if (!busy) {
          await tester.ensureVisible(button);
          await tester.tap(button);
          expect(requests, 1);
        }
      }
      expect(
        find.text(FormStrings.measurementApprovalRequired),
        !approved && name != 'awaiting setup' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(FormStrings.measurementRuntimePending),
        name == 'awaiting setup' ? findsOneWidget : findsNothing,
      );
      if (enabled && !approved && requested) {
        expect(
          find.text(
            FormStrings.measurementApprovalRequested(
              DateFormat.yMd('cs').format(requestedAt.toLocal()),
            ),
          ),
          findsOneWidget,
        );
      }
      expect(find.text(FormStrings.gtmContainer), findsOneWidget);
      expect(
        find.text(FormStrings.measurementUnitDisabled),
        enabled ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
    'measurement help uses the published guide for a German interface',
    (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      String? opened;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          opened = (call.arguments as Map)['url'] as String;
        }
        return true;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final fixture = WidgetEnvironmentFixture(
        locale: const Locale('de'),
        translations: jsonDecode(
          File('assets/translations/de.json').readAsStringSync(),
        ),
      );
      await fixture.pumpWidget(
        tester,
        MaterialApp(
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: UnitMeasurementHelpButton(
              UnitMeasurementHelp.basics,
              label: FormStrings.measurementBasics,
            ),
          ),
        ),
      );
      final steps = FormStrings.cmsInstallSteps('html');
      expect(steps.first, contains(FormStrings.embedAction));
      expect(steps[1], contains(FormStrings.cmsEnableImport));
      expect(steps[1], contains(FormStrings.cmsImportLabel));
      expect(
        steps[1].indexOf(FormStrings.cmsEnableImport),
        lessThan(steps[1].indexOf(FormStrings.cmsImportLabel)),
      );
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();
      expect(
        opened,
        'https://vstupenky.online/napoveda/mereni-formularu/#zapnuti',
      );
    },
  );
}
