import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/fonts/font_family_picker.dart';
import 'package:fstapp/components/fonts/form_font_catalog.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/form_design_settings.dart';

class _Fonts implements FormFontCatalog {
  @override
  List<String> get families => ['Inter', 'Roboto'];
  @override
  TextStyle getFont(String family) => TextStyle(fontFamily: family);
  @override
  TextTheme getTextTheme(String family, TextTheme base) =>
      base.apply(fontFamily: family);
}

void main() {
  setUpAll(() => Localization.load(const Locale('cs'),
      translations: Translations(
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>)));

  testWidgets(
      'failed catalog download preserves design and retries before choosing a font',
      (tester) async {
    final first = Completer<FormFontCatalog>();
    final retry = Completer<FormFontCatalog>();
    final form = FormModel()..fontFamily = 'Inter';
    var loads = 0;
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
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
    expect(form.fontFamily, 'Inter');
    expect(changes, 0);

    await tester.ensureVisible(find.text(CommonStrings.retry));
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pump();
    expect(loads, 2);
    retry.complete(_Fonts());
    await tester.pumpAndSettle();
    expect(find.byType(FontFamilyPicker), findsOneWidget);
    expect(find.text(FormStrings.fontLoadFailed), findsNothing);
    expect(form.fontFamily, 'Inter');

    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Roboto').last);
    await tester.pumpAndSettle();
    expect(form.fontFamily, 'Roboto');
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });
}
