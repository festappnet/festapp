import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_design_settings.dart';

late WidgetEnvironmentFixture _environment;

class _Fonts implements FormFontCatalog {
  @override
  Future<void> ensureFamily(String family) async {}
  @override
  List<String> get families => ['Inter', 'Roboto'];
  @override
  Future<TextStyle> previewStyle(String family) async => getFont(family);
  @override
  TextStyle getFont(String family) => TextStyle(fontFamily: family);
  @override
  TextTheme getTextTheme(String family, TextTheme base) =>
      base.apply(fontFamily: family);
}

void main() {
  WidgetEnvironmentFixture.register();
  setUpAll(() => _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>));

  testWidgetsWithEnvironment(() => _environment,
      'failed catalog download preserves design and retries before choosing a font',
      (tester) async {
    final first = Completer<FormFontCatalog>();
    final retry = Completer<FormFontCatalog>();
    final form = FormEditorDraft();
    form.definition = form.definition.withFontFamily('Inter');
    var loads = 0;
    var changes = 0;
    await _environment.pumpWidget(
        tester,
        MaterialApp(builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: FormDesignSettings(
              form: form,
              onChanged: () => changes++,
              loadFonts: () => ++loads == 1 ? first.future : retry.future,
            ),
          ),
        ));
    expect(find.byType(FontFamilyPicker), findsNothing);
    expect(find.text(FormStrings.customColors), findsOneWidget);
    first.completeError(StateError('temporary network failure'));
    await tester.pump();
    expect(find.text(FormStrings.fontLoadFailed), findsOneWidget);
    expect(form.definition.fontFamily, 'Inter');
    expect(changes, 0);

    await tester.ensureVisible(find.text(CommonStrings.retry));
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pump();
    expect(loads, 2);
    retry.complete(_Fonts());
    await tester.pumpAndSettle();
    expect(find.byType(FontFamilyPicker), findsOneWidget);
    expect(find.text(FormStrings.fontLoadFailed), findsNothing);
    expect(form.definition.fontFamily, 'Inter');

    final choice = find.descendant(of: find.byType(FontFamilyPicker),
        matching: find.byType(DropdownButtonFormField<String>));
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto').last);
    await tester.pumpAndSettle();
    expect(form.definition.fontFamily, 'Roboto');
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });
}
