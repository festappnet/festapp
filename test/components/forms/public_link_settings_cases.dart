import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:flutter/foundation.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
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
import 'package:fstapp/components/forms/views/form_public_link.dart';
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

  testWidgetsWithEnvironment(() => _environment,
      'failed rename retains saved address and discard restores it',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel(isEditor: true),
        occasion: OccasionModel(
            isOpen: true,
            isHidden: false,
            isPromoted: false,
            features: [FormFeature(code: 'form')]));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
    final form = FormEditorDraft(
        id: 1, link: 'Legacy_address', title: 'Original', data: {});
    var saves = 0;
    await _environment.pumpWidget(
        tester,
        MaterialApp(
            home: FormSettingsContent(
          bankConnectionChanges: _bankChanges,
          formLink: 'Legacy_address',
          loadBundle: (_) async => FormEditBundle(
              form: form,
              productTypes: [],
              products: [],
              availableBankAccounts: []),
          saveForm: (_) async {
            saves++;
            throw StateError('link already reserved');
          },
        )));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextFormField, FormStrings.labelFormLink);
    await tester.enterText(field, 'new-address');
    expect(tester.widget<FormPublicLink>(find.byType(FormPublicLink)).savedLink,
        'Legacy_address');
    await tester.widget<EditorActionBar>(find.byType(EditorActionBar)).onSave();
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(tester.widget<FormPublicLink>(find.byType(FormPublicLink)).savedLink,
        'Legacy_address');
    await tester
        .widget<EditorActionBar>(find.byType(EditorActionBar))
        .onDiscard();
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextFormField>(field).controller!.text, 'Legacy_address');
    // Saving an unchanged legacy slug still reaches the server.
    await tester.enterText(
        find.widgetWithText(TextFormField, FormStrings.labelFormTitle),
        'Changed');
    await tester.widget<EditorActionBar>(find.byType(EditorActionBar)).onSave();
    expect(saves, 2);
  });
}
