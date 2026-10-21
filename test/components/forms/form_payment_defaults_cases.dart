import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:flutter/foundation.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:festapp_core/forms.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

late WidgetEnvironmentFixture _environment;

late ValueNotifier<({int accountId, int revision})> _bankChanges;
void main() {
  setUp(() {
    _bankChanges = ValueNotifier((accountId: 0, revision: 0));
    addTearDown(_bankChanges.dispose);
  });
  WidgetEnvironmentFixture.register();
  setUpAll(() => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));

  for (final override in [null, false, true]) {
    testWidgetsWithEnvironment(() => _environment,
        'preserves reminder override $override on unrelated save and can restore inheritance',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          capabilities: {
            AuthorizationCapabilities.ordersWrite: true,
            AuthorizationCapabilities.occasionsWrite: true
          },
          occasionUser: OccasionUserModel(isEditor: true),
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [
                FormFeature(
                    code: 'form',
                    reminderIsEnabled: true,
                    reminderIntervalSeconds: 86400,
                    deadlineDurationSeconds: 604800)
              ]));
      addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
      final form = FormEditorDraft(link: 'test', title: 'Original', data: {
        if (override != null) FormDefinition.metaIsReminderEnabled: override,
      });
      var saves = 0;
      await _environment.pumpWidget(
          tester,
          MaterialApp(
              home: FormSettingsContent(
            bankConnectionChanges: _bankChanges,
            formLink: 'test',
            loadBundle: (_) async => FormEditBundle(
                form: form,
                productTypes: [],
                products: [],
                availableBankAccounts: []),
            saveForm: (_) async {
              saves++;
            },
          )));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<EditorActionBar>(find.byType(EditorActionBar))
              .hasChanges,
          isFalse);
      final title =
          find.widgetWithText(TextFormField, FormStrings.labelFormTitle);
      await tester.enterText(title, 'Changed');
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(form.definition.data?[FormDefinition.metaIsReminderEnabled],
          override);
      expect(
          form.definition.data!
              .containsKey(FormDefinition.metaIsReminderEnabled),
          override != null);
      expect(form.definition.deadlineDurationSeconds, isNull);
      expect(
          form.definition.data!
              .containsKey(FormDefinition.metaReminderIntervalSeconds),
          isFalse);
      if (override != null) {
        final reminder = find.byWidgetPredicate((w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == FormStrings.labelEnableReminders);
        tester
            .widget<DropdownButtonFormField<String>>(reminder)
            .onChanged!('inherit');
        await tester.pumpAndSettle();
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(
            form.definition.data!
                .containsKey(FormDefinition.metaIsReminderEnabled),
            isFalse);
      }
      final interval =
          find.widgetWithText(TextFormField, FormStrings.labelReminderInterval);
      final deadline =
          find.widgetWithText(TextFormField, FormStrings.labelDeadlineDays);
      await tester.enterText(interval, '2');
      await tester.enterText(deadline, '4');
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(form.definition.data![FormDefinition.metaReminderIntervalSeconds],
          172800);
      expect(form.definition.deadlineDurationSeconds, 345600);
      await tester.enterText(deadline, '0');
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(form.definition.deadlineDurationSeconds, 0);
      await tester.enterText(interval, '');
      await tester.enterText(deadline, '');
      await tester
          .widget<EditorActionBar>(find.byType(EditorActionBar))
          .onSave();
      await tester.pumpAndSettle();
      expect(
          form.definition.data!
              .containsKey(FormDefinition.metaReminderIntervalSeconds),
          isFalse);
      expect(form.definition.deadlineDurationSeconds, isNull);
      await _environment.pumpWidget(tester, const SizedBox.shrink());
    });
  }
}
