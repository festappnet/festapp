import 'package:fstapp/widgets/dependency_material_bridge.dart';

import 'dart:convert';
import 'dart:io';

import 'package:festapp_core/forms.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:fstapp/components/forms/models/holder_models/form_holder.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/forms/views/form_capacity_settings.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/forms/widgets_editor/form_fields_generator.dart';
import 'package:fstapp/services/decimal_input.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(
    () => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    ),
  );

  test(
    'legacy empty selections do not prevent the public form from loading',
    () {
      for (final type in [
        FormMetadata.fieldTypeSelectOne,
        FormMetadata.fieldTypeSelectMany,
      ]) {
        for (final data in [
          null,
          {},
          {'options': null},
          {'options': 'invalid'},
        ]) {
          final definition = FormDefinition.fromJson({
            'id': 1,
            'fields': [
              {'id': 22, 'type': 'email'},
              {'id': 23, 'type': type, 'is_required': true, 'data': data},
            ],
          });
          expect(FormHolder.fromDefinition(definition).fields, hasLength(2));
        }
      }
    },
  );

  test('decimal parser accepts comma/dot and rejects nonfinite or ambiguous values', () {
    for (final text in ['1,5', '1.5', ' 1,5 ']) {
      expect(
        DecimalInput.positiveDurationSeconds(text, secondsPerUnit: 3600),
        5400,
      );
    }
    for (final text in [
      '',
      'NaN',
      'Infinity',
      '-1',
      '0',
      '1,2.3',
      '1 000',
      '0,00001',
      '99999999999999999999999999999',
    ]) {
      expect(
        DecimalInput.positiveDurationSeconds(text, secondsPerUnit: 3600),
        isNull,
      );
    }
  });

  testWidgetsWithEnvironment(
    () => _environment,
    'selection draft cannot save without options and remains editable',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final field = FormFieldDraft(
        id: 23,
        type: FormMetadata.fieldTypeSelectOne,
        title: 'Group',
        isRequired: true,
      );
      final bundle = FormEditBundle(
        form: FormEditorDraft(occasionId: 1, relatedFields: [field]),
        productTypes: [],
        products: [],
        availableBankAccounts: [],
      );
      var saves = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: FormEditorContent.prototype(
            bundle: bundle,
            onPrototypeSave: (_) => saves++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(FormStrings.selectionOptionsRequired), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, 'Edited group');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, CommonStrings.save));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(field.definition.title, 'Edited group');
      final option = find.widgetWithText(
        TextField,
        FormStrings.enterOptionValue,
      );
      await tester.enterText(option, 'Morning');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      expect(field.options.single.title, 'Morning');
      expect(
        find.descendant(
          of: find.byType(FormFieldsGenerator),
          matching: find.text(FormStrings.selectionOptionsRequired),
        ),
        findsNothing,
      );
      await tester.tap(find.widgetWithText(FilledButton, CommonStrings.save));
      await tester.pumpAndSettle();
      expect(saves, 1);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'capacity dialog accepts Czech hours and preserves draft until Apply',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final form = FormEditorDraft(
        link: 'test',
        participantCapacity: 12,
        waitlistEnabled: true,
        waitlistOfferDurationSeconds: 3600,
        data: {},
      );
      var changes = 0;
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: FormCapacitySettings(
              form: form,
              canEdit: true,
              onChanged: () => changes++,
            ),
          ),
        ),
      );
      await tester.tap(find.text(WaitlistStrings.settings));
      await tester.pumpAndSettle();
      expect(find.byType(FormCapacityDialog), findsOneWidget);
      final hours = find.widgetWithText(
        TextFormField,
        WaitlistStrings.durationHours,
      );
      for (final invalid in ['Infinity', 'NaN', '-1', '0', '999999999999']) {
        await tester.enterText(hours, invalid);
        await tester.tap(find.text(WaitlistStrings.applySettings));
        await tester.pumpAndSettle();
        expect(find.text(WaitlistStrings.positiveNumber), findsOneWidget);
        expect(form.definition.waitlistOfferDurationSeconds, 3600);
        expect(changes, 0);
      }
      await tester.enterText(hours, '1,5');
      expect(form.definition.waitlistOfferDurationSeconds, 3600);
      await tester.tap(find.text(WaitlistStrings.applySettings));
      await tester.pumpAndSettle();
      expect(changes, 1);
      expect(find.byType(FormCapacityDialog), findsNothing);
      expect(form.definition.waitlistOfferDurationSeconds, 5400);
      expect(form.toEditedJson()['waitlist_offer_duration_seconds'], 5400);
    },
  );
}
