import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/unit/views/unit_measurement_settings.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();

  for (final canEdit in [true, false]) {
    testWidgets('destinations remain discoverable when off; canEdit=$canEdit', (
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
      expect(find.text(FormStrings.gtmContainer), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.tap(find.text(FormStrings.measurementTitle));
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.gtmContainer), findsOneWidget);
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
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged == null, !canEdit);
      if (canEdit) {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(enabled, isTrue);
        final enabledPrivacyField = tester.widget<TextFormField>(privacyField);
        expect(enabledPrivacyField.validator!(''), FormStrings.measurementPrivacyUrlRequired);
        expect(enabledPrivacyField.validator!('https://organizer.example/privacy'), isNull);
        gtm.clear();
        scripts.clear();
        expect(enabledPrivacyField.validator!(''), isNull);
        scripts.text = '<script>/* saved */</script>';
        expect(enabledPrivacyField.validator!(''), FormStrings.measurementPrivacyUrlRequired);
        gtm.text = 'GTM-ABCD';
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(enabled, isFalse);
        expect(tester.widget<TextFormField>(privacyField).validator!(''), isNull);
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
      final tile = ExpansibleController();
      addTearDown(gtm.dispose);
      addTearDown(privacy.dispose);
      addTearDown(scripts.dispose);
      addTearDown(tile.dispose);
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
                  canEdit: canEdit,
                  gtmController: gtm,
                  scriptsController: scripts,
                  privacyUrlController: privacy,
                  controller: tile,
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
      expect(find.text(FormStrings.gtmContainer), findsNothing);
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
        tile.expand();
        await tester.pumpAndSettle();
        expect(
          find.text(FormStrings.measurementPrivacyUrlRequired),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
