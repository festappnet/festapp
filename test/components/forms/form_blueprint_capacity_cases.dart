import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/forms/waitlist_strings.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));
  for (final enabled in [false, true]) {
    testWidgetsWithEnvironment(
        () => _environment, 'stored blueprint with feature enabled=$enabled',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
            FormFeature(code: 'form'),
            SimpleFeature(code: 'blueprint', isEnabled: enabled)
          ]));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final form = FormEditorDraft(link: 'test', title: 'Test', blueprint: 42);
      FormEditorDraft? saved;
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: FormSettingsContent(
            formLink: 'test',
            loadBundle: (_) async => FormEditBundle(
                form: form,
                productTypes: [],
                products: [],
                availableBankAccounts: []),
            saveForm: (value) async {
              saved = value;
            },
          )));
      await tester.pumpAndSettle();
      final capacity =
          find.widgetWithText(TextFormField, WaitlistStrings.capacity);
      expect(capacity, enabled ? findsNothing : findsOneWidget);
      if (!enabled) {
        await tester.enterText(capacity, '50');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(saved?.definition.participantCapacity, 50);
        expect(saved?.definition.blueprint, 42);
      }
    });
  }
}
