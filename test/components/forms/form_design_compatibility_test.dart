import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_design_settings.dart';
import 'package:fstapp/components/occasion/setup/occasion_setup_appearance.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

class _Fonts implements FormFontCatalog {
  @override
  List<String> get families => ['Roboto', 'Roboto Slab'];
  @override
  Future<void> ensureFamily(String family) async {}
  @override
  TextStyle getFont(String family) => TextStyle(fontFamily: family);
  @override
  Future<TextStyle> previewStyle(String family) async => getFont(family);
  @override
  TextTheme getTextTheme(String family, TextTheme base) => base;
}

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ),
    );
  });

  test('legacy one-color form has no invented secondary or mode override', () {
    final form = FormEditorDraft();
    form.definition = form.definition.withPrimaryColor(0xff216445);
    final before = form.toEditedJson();
    final appearance = OccasionSetupAppearance.read({
      'formDraft': form.definition.toJson(),
    });
    expect(appearance['primary'], '216445');
    expect(appearance['secondary'], '216445');
    expect(appearance['gradient'], false);
    expect(form.definition.backgroundMode, isNull);
    expect(form.definition.secondaryColor, isNull);
    expect(form.toEditedJson(), before);
  });

  testWidgetsWithEnvironment(
    () => environment,
    'form editor round-trips one and two colors to the wizard',
    (tester) async {
      final form = FormEditorDraft();
      form.definition = form.definition
          .withPrimaryColor(0xff14284b)
          .withSecondaryColor(0xffa87f28)
          .withFontFamily('Roboto Slab')
          .withBackgroundMode('gradient');
      var changes = 0;
      await environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: FormDesignSettings(
              form: form,
              onChanged: () => changes++,
              loadFonts: () async => _Fonts(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(form.definition.primaryColor, 0xff14284b);
      expect(form.definition.secondaryColor, 0xffa87f28);
      expect(form.definition.fontFamily, 'Roboto Slab');
      expect(form.definition.backgroundMode, 'gradient');
      expect(
        form.toEditedJson()['settings']['design']['background_mode'],
        'gradient',
      );
      final draft = <String, dynamic>{
        'appearance': {...OccasionSetupAppearance.presets.first},
        'formDraft': form.definition.toJson(),
      };
      final appearance = OccasionSetupAppearance.read(draft);
      expect(appearance['primary'], '14284B');
      expect(appearance['secondary'], 'A87F28');
      expect(appearance['fontFamily'], 'Roboto Slab');
      expect(appearance['gradient'], true);
      final toggle = find.widgetWithText(
        SwitchListTile,
        FormStrings.appearanceLabel('two_color_gradient'),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(form.definition.backgroundMode, 'solid');
      expect(
        form.toEditedJson()['settings']['design']['background_mode'],
        'solid',
      );
      expect(form.definition.secondaryColor, 0xffa87f28);
      expect(
        find.text(FormStrings.appearanceLabel('secondary_color')),
        findsNothing,
      );
      Future<void> pick(String label, String hex) async {
        final row = find.ancestor(
          of: find.text(label),
          matching: find.byType(Row),
        );
        final control = find.descendant(
          of: row.first,
          matching: find.byType(GestureDetector),
        );
        await tester.ensureVisible(control.first);
        await tester.tap(control.first);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, FormStrings.hexCodeLabel),
          hex,
        );
        await tester.tap(find.text(FormStrings.buttonGotIt));
        await tester.pumpAndSettle();
      }

      await pick(FormStrings.primaryColor, '#216445');
      expect(form.definition.primaryColor, 0xff216445);
      expect(form.definition.secondaryColor, 0xffa87f28);

      draft['formDraft'] = form.definition.toJson();
      final solid = OccasionSetupAppearance.read(draft);
      expect(solid['gradient'], false);
      expect(solid['primary'], '216445');
      expect(solid['secondary'], 'A87F28');
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(form.definition.backgroundMode, 'gradient');
      expect(form.definition.secondaryColor, 0xffa87f28);
      expect(
        find.text(FormStrings.appearanceLabel('secondary_color')),
        findsOneWidget,
      );
      await pick(FormStrings.appearanceLabel('secondary_color'), '#146475');
      expect(form.definition.secondaryColor, 0xff146475);
      draft['formDraft'] = form.definition.toJson();
      final gradient = OccasionSetupAppearance.read(draft);
      expect(gradient['primary'], '216445');
      expect(gradient['secondary'], '146475');
      expect(gradient['gradient'], true);
      expect(changes, greaterThanOrEqualTo(4));
      expect(tester.takeException(), isNull);
    },
  );
}
