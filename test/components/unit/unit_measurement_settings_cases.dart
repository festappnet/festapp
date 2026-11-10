import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/unit/views/unit_measurement_settings.dart';
import 'package:fstapp/components/unit/unit_measurement_approval.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();

  for (final canEdit in [true, false]) {
    testWidgets('destinations and consent bridge opt-in when off; canEdit=$canEdit', (
      tester,
    ) async {
      final fixture = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ) as Map<String, dynamic>,
      );
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
        find.widgetWithText(SwitchListTile, FormStrings.measurementUnitEnabled),
        findsOneWidget,
      );
      expect(find.text(FormStrings.measurementUnitDisabled), findsOneWidget);
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
        SwitchListTile, FormStrings.measurementConsentBridge,
      );
      final bridge = tester.widget<SwitchListTile>(bridgeSwitch);
      expect(bridge.value, isFalse);
      expect(bridge.onChanged == null, !canEdit);
      expect(find.text(FormStrings.measurementConsentBridgeConfirmation), findsOneWidget);
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
        final enabledPrivacyField = tester.widget<TextFormField>(privacyField);
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
    });
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
      final controllers = List.generate(5, (_) => TextEditingController());
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
