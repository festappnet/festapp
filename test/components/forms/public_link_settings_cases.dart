import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:fstapp/components/forms/views/form_embed_code.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
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

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));

  test('embed code uses tenant, escaped attributes and one public saved URL',
      () {
    for (final automatic in [true, false]) {
      for (final inheritStyle in [true, false]) {
        final code = formEmbedCode(
            tenantUrl: 'https://tenant.example/',
            savedLink: 'Legacy &/č',
            title: 'Order "tickets"',
            fallbackLabel: 'Open <order>',
            automatic: automatic,
            inheritStyle: inheritStyle);
        expect(
            code,
            contains(
                'https://tenant.example/form/Legacy%20%26%2F%C4%8D?embed=1'));
        expect(code, contains('Order &quot;tickets&quot;'));
        expect(code, contains('Open &lt;order&gt;'));
        expect(code.contains(RegExp(r'\bdata-festapp-embed(?:\s|>)')),
            automatic || inheritStyle);
        expect(code.contains('data-festapp-style="inherit"'), inheritStyle);
        expect(code.contains('data-festapp-height="fixed"'),
            !automatic && inheritStyle);
        expect(code.contains('<script'), automatic || inheritStyle);
        expect(code, contains('height="800"'));
        expect(code, isNot(contains('sandbox')));
      }
    }
    expect(
        () => formEmbedCode(
            tenantUrl: 'https://tenant.example',
            savedLink: '',
            title: 'Order',
            fallbackLabel: 'Open'),
        throwsArgumentError);
  });

  testWidgetsWithEnvironment(() => _environment,
      'embed action copies only saved address and is absent for a new form',
      (tester) async {
    await _environment.pumpWidget(
        tester,
        const MaterialApp(
            home: Scaffold(
                body: FormPublicLink(link: 'draft', savedLink: 'saved'))));
    await tester.tap(find.text(FormStrings.embedAction));
    await tester.pumpAndSettle();
    final copies = tester
        .widgetList<CopyButton>(find.byType(CopyButton))
        .map((w) => w.value);
    expect(copies.any((v) => v.contains('/form/saved?embed=1')), isTrue);
    expect(copies.any((v) => v.contains('/form/draft')), isFalse);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue);
    expect(
        copies.any((v) => v.contains('data-festapp-style="inherit"')), isTrue);
    await tester.tap(find.text(FormStrings.embedInheritStyle));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    expect(
        tester
            .widgetList<CopyButton>(find.byType(CopyButton))
            .any((button) => button.value.contains('data-festapp-style')),
        isFalse);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await _environment.pumpWidget(
        tester,
        const MaterialApp(
            home: Scaffold(body: FormPublicLink(link: 'new-draft'))));
    await tester.pumpAndSettle();
    expect(find.text(FormStrings.embedAction), findsNothing);
    expect(find.text(FormStrings.embedSaveFirst), findsOneWidget);
  });

  testWidgetsWithEnvironment(() => _environment,
      'failed rename retains saved address and discard restores it',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
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
