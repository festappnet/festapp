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
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.onChanged == null, !canEdit);
      if (canEdit) {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(enabled, isTrue);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(enabled, isFalse);
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
}
