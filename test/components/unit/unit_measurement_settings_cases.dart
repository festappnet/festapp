import 'dart:ui' as ui;
import 'dart:async';

import 'package:fstapp/components/unit/views/unit_website_consent_settings.dart';
import 'package:fstapp/components/unit/unit_website_consent.dart';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/unit/views/unit_measurement_settings.dart';
import 'package:fstapp/components/unit/unit_measurement_approval.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
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
      expect(find.text(CommonStrings.loading), findsNothing);
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '42',
      );
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsSaveDraft));
      await tester.tap(find.text(FormStrings.cmsSaveDraft));
      await tester.pumpAndSettle();
      expect(draft, {'provider': 'complianz', 'policyId': '42'});
    },
  );

  testWidgets(
    'Complianz pending probe does not block changing provider and ignores late result',
    (tester) async {
      final pending = Completer<String>();
      await pumpConsent(tester, detect: (_) => pending.future);
      await tester.pumpAndSettle();
      final selectors = tester
          .widgetList<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .toList();
      expect(selectors.every((selector) => selector.onChanged != null), true);
      // Drive the same callback used by keyboard and dropdown selection.
      selectors.last.onChanged!('cookiebot');
      await tester.pumpAndSettle();
      expect(find.text(CommonStrings.loading), findsNothing);
      pending.complete('42');
      await tester.pumpAndSettle();
      expect(find.text('${FormStrings.cmsPolicyId}: 42'), findsNothing);
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
      await tester.pumpAndSettle();
      expect(find.text('${FormStrings.cmsPolicySaved}: 41'), findsOneWidget);
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, FormStrings.cmsPolicyId);
      expect(tester.widget<TextField>(field).controller!.text, '41');
      await tester.enterText(field, '43');
      await tester.ensureVisible(find.text(FormStrings.cmsPolicyReload));
      await tester.tap(find.text(FormStrings.cmsPolicyReload));
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsConfirm));
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsPolicyChanged), findsOneWidget);
      expect(find.text('${FormStrings.cmsPolicyId}: 43'), findsOneWidget);
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text(FormStrings.cmsConfirm));
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
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
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextField, FormStrings.cmsPolicyId);
      expect(tester.widget<TextField>(field).enabled, true);
      expect(tester.widget<TextField>(field).controller!.text, '42');
      pending.complete('43');
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(
        attempts,
        1,
        reason: 'saved website needs neither platform approval nor existing binding',
      );
      expect(find.text(CommonStrings.loading), findsOneWidget);
      saved = false;
      await pump();
      await tester.pumpAndSettle();
      expect(find.text(CommonStrings.loading), findsNothing);
      pending.complete('42');
      await tester.pumpAndSettle();
      expect(find.text('${FormStrings.cmsPolicyId}: 42'), findsNothing);
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
      await tester.pumpAndSettle();
      expect(find.text(CommonStrings.loading), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsPolicyDetectionFailed), findsOneWidget);
      expect(find.text(CommonStrings.loading), findsNothing);
      pending.complete('42');
      await tester.pumpAndSettle();
      expect(find.text('${FormStrings.cmsPolicyId}: 42'), findsNothing);
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '43',
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '43'), findsOneWidget);
    },
  );

  testWidgets(
    'Complianz detects read-only ID, reloads and offers manual fallback',
    (tester) async {
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
      await tester.pumpAndSettle();
      expect(find.text('${FormStrings.cmsPolicyId}: 42'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsPolicyReload));
      await tester.pumpAndSettle();
      expect(find.text('${FormStrings.cmsPolicyId}: 43'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      await tester.tap(find.text(FormStrings.cmsPolicyReload));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsPolicyDetectionFailed), findsOneWidget);
      expect(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        findsNothing,
      );
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '44',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await tester.pumpAndSettle();
      expect(pinned, {'provider': 'complianz', 'policyId': '44'});
    },
  );
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
      Future<void> pump() => tester.pumpWidget(
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        'invalid',
      );
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsPolicyIdInvalid), findsOneWidget);
      expect(confirm().onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '42',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await tester.pumpAndSettle();
      expect(confirmations, 1);
      expect(version, 1);
      expect(find.text(FormStrings.cmsConfirm), findsNothing);
      expect(find.text(FormStrings.cmsSaveDraft), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await tester.tap(find.text(FormStrings.cmsExport));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.text(FormStrings.cmsShowConfiguration));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsOneWidget);
      expect(
        version,
        1,
        reason: 'getting configuration never reconfirms coverage',
      );
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
      await tester.tap(find.text(FormStrings.cmsCopy));
      await tester.pumpAndSettle();
      expect(copied, contains('"schemaVersion": 1'));
      expect(find.text(CommonStrings.copiedToClipboard), findsOneWidget);
      await tester.tap(find.text('Complianz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cookiebot').last);
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      expect(confirm().onPressed, isNull);
      expect(find.text(FormStrings.cmsExport), findsNothing);
      expect(find.text(FormStrings.cmsSaveDraft), findsNothing);
      expect(find.text(FormStrings.cmsChangesPending), findsOneWidget);
      await tester.tap(find.text(CommonStrings.discardChanges));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsExport), findsOneWidget);
      expect(find.text(FormStrings.cmsConfirm), findsNothing);
      expect(
        version,
        1,
        reason: 'discarding edits preserves the active binding',
      );
      for (final suspendedState in ['approval_required', 'unavailable']) {
        state = suspendedState;
        await pump();
        await tester.pumpAndSettle();
        await tester.tap(find.text(FormStrings.cmsPolicyManual));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, FormStrings.cmsPolicyId),
          '43',
        );
        await tester.pumpAndSettle();
        expect(
          find.text(FormStrings.cmsSaveDraft),
          findsNothing,
          reason: 'a temporarily unavailable confirmed binding cannot become a draft by accident',
        );
        await tester.tap(find.text(CommonStrings.discardChanges));
        await tester.pumpAndSettle();
        expect(version, 1);
        expect(confirmations, 1);
      }
      state = 'ready';
      await pump();
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsDisable));
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complianz'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CookieConsent v3').last);
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsAdvancedCategories), findsOneWidget);
      expect(find.text(FormStrings.cmsAnalyticsCategory), findsNothing);
      await tester.tap(find.text(FormStrings.cmsAdvancedCategories));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsAnalyticsCategory), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsAnalyticsCategory),
        'marketing',
      );
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.cmsCategoriesInvalid), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, FormStrings.cmsConfirm),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('CookieConsent v3'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cookiebot').last);
      await tester.pumpAndSettle();
      expect(find.text('Cookiebot CBID'), findsNothing);
      expect(find.text(FormStrings.cmsAnalyticsCategory), findsNothing);
      await tester.tap(find.text('WordPress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wix').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Wix').first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('WordPress').last);
      await tester.pumpAndSettle();
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
                save: (_, __, ___, ____, _____, ______) async =>
                    throw StateError('website_consent_conflict'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsPolicyManual));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, FormStrings.cmsPolicyId),
        '42',
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsConfirm));
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      sites = ['https://poradatel.cz', 'https://tanec.cz'];
      saved = false;
      await pump();
      await tester.pumpAndSettle();
      expect(find.text('https://poradatel.cz'), findsOneWidget);
      saved = true;
      await pump();
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('https://tanec.cz'), findsOneWidget);
      saved = true;
      await pump();
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Measurement settings'));
      await tester.pumpAndSettle();
      final exportButton = find.widgetWithText(
        FilledButton,
        FormStrings.cmsExport,
      );
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text(FormStrings.cmsShowConfiguration));
      await tester.pumpAndSettle();
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
    'invalid',
    'removed',
    'desktop',
    'large text',
  ]) {
    testWidgets('saved website UX independent of runtime approval: $state', (
      tester,
    ) async {
      tester.view.physicalSize = Size(state == 'desktop' ? 1000 : 390, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controllers = List.generate(6, (_) => TextEditingController());
      for (final controller in controllers) {
        addTearDown(controller.dispose);
      }
      const site = 'https://poradatel.cz';
      controllers[0].text = state == 'removed' ? '' : site;
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
        'can_request': state != 'approved' && state != 'requested',
        'saved_origins': saved,
        'approved_origins': state == 'approved' ? [site] : <String>[],
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
      if (state == 'invalid') {
        await tester.enterText(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField && widget.controller == controllers[0],
          ),
          '$site/vstupenky',
        );
        await tester.pumpAndSettle();
        expect(
          find.text(FormStrings.measurementWebsitesInvalid),
          findsOneWidget,
        );
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
      final label = switch (state) {
        'draft' => FormStrings.measurementWebsiteDraft,
        'unrequested' => FormStrings.measurementWebsiteSaved,
        'requested' => FormStrings.measurementWebsiteSaved,
        'retry' => FormStrings.measurementWebsiteSaved,
        'unavailable' => FormStrings.measurementWebsiteSaved,
        'approved' => FormStrings.measurementWebsiteSaved,
        _ => null,
      };
      if (label != null) expect(find.text('$site: $label'), findsOneWidget);
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
        expect(find.text(FormStrings.measurementTitle), findsOneWidget);
        expect(find.text(FormStrings.gtmContainer), findsOneWidget);
        expect(
          find.widgetWithText(
            SwitchListTile,
            FormStrings.measurementUnitEnabled,
          ),
          findsOneWidget,
        );
        expect(find.text(FormStrings.measurementUnitDisabled), findsOneWidget);
        expect(
          find.text(
            'https://approved.example: ${FormStrings.measurementWebsiteSaved}',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'https://pending.example: ${FormStrings.measurementWebsiteSaved}',
          ),
          findsOneWidget,
        );
        final websitesField = tester.widget<TextFormField>(
          find.byWidgetPredicate(
            (w) => w is TextFormField && w.controller == websites,
          ),
        );
        expect(websitesField.enabled, canEdit);
        expect(
          websitesField.validator!(
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
            websitesField.validator!(invalid),
            FormStrings.measurementWebsitesInvalid,
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
        final bridge = tester.widget<SwitchListTile>(bridgeSwitch);
        expect(bridge.value, isFalse);
        expect(bridge.onChanged == null, !canEdit);
        expect(
          find.text(FormStrings.measurementConsentBridgeConfirmation),
          findsOneWidget,
        );
        if (canEdit) {
          await tester.ensureVisible(bridgeSwitch);
          await tester.tap(bridgeSwitch);
          await tester.pumpAndSettle();
          expect(consentBridge, isTrue);
        }
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
                  'organization_allowed': approved,
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
      if (enabled && !approved) {
        expect(button, findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(button).onPressed != null,
          canEdit && !requested && !busy,
        );
        expect(
          find.text(
            requested
                ? FormStrings.measurementApprovalRequested(
                    DateFormat.yMd('cs').format(requestedAt.toLocal()),
                  )
                : FormStrings.measurementApprovalRequired,
          ),
          findsOneWidget,
        );
        if (canEdit && !requested && !busy) {
          await tester.ensureVisible(button);
          await tester.tap(button);
          expect(requests, 1);
        }
      } else {
        expect(button, findsNothing);
        expect(
          find.text(FormStrings.measurementApprovalRequired),
          findsNothing,
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
}
