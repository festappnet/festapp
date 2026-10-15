import 'dart:convert';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/theme_config.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('Futura')
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
  });

  for (final defaultEnabled in [true, false]) {
    for (final override in [null, false, true]) {
      testWidgets(
          'preserves override $override with default $defaultEnabled and restores inheritance',
          (tester) async {
        tester.view.physicalSize = const Size(1600, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
            occasionUser: OccasionUserModel(isEditor: true),
            occasion: OccasionModel(
                isOpen: true,
                isHidden: false,
                isPromoted: false,
                features: [
                  FormFeature(
                      code: 'form',
                      reminderIsEnabled: defaultEnabled,
                      reminderIntervalSeconds: 86400,
                      deadlineDurationSeconds: 604800)
                ]));
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        final form = FormModel(link: 'test', title: 'Original', data: {
          if (override != null) FormModel.metaIsReminderEnabled: override,
        });
        var saves = 0;
        await tester.pumpWidget(RepaintBoundary(
            key: const ValueKey('reminder-preview'),
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: ThemeConfig.theme(),
                home: FormSettingsContent(
                  formLink: 'test',
                  loadBundle: (_) async => FormEditBundle(
                      form: form,
                      formFields: [],
                      productTypes: [],
                      products: [],
                      availableBankAccounts: []),
                  saveForm: (_) async {
                    saves++;
                  },
                ))));
        await tester.pumpAndSettle();
        if (defaultEnabled &&
            override == null &&
            Platform.environment['REMINDER_UI_ARTIFACT'] != null) {
          tester.view.physicalSize = const Size(800, 1400);
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('reminder-preview')));
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            File(Platform.environment['REMINDER_UI_ARTIFACT']!)
                .writeAsBytesSync(bytes!.buffer.asUint8List());
            image.dispose();
          });
          tester.view.physicalSize = const Size(1600, 2200);
          await tester.pumpAndSettle();
        }
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
        expect(form.data?[FormModel.metaIsReminderEnabled], override);
        expect(form.data!.containsKey(FormModel.metaIsReminderEnabled),
            override != null);
        expect(form.deadlineDurationSeconds, isNull);
        expect(form.data!.containsKey(FormModel.metaReminderIntervalSeconds),
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
              form.data!.containsKey(FormModel.metaIsReminderEnabled), isFalse);
        }
        if (!defaultEnabled) {
          final reminder = find.byWidgetPredicate((w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == FormStrings.labelEnableReminders);
          tester
              .widget<DropdownButtonFormField<String>>(reminder)
              .onChanged!('enabled');
          await tester.pumpAndSettle();
        }
        final interval = find.widgetWithText(
            TextFormField, FormStrings.labelReminderInterval);
        final deadline =
            find.widgetWithText(TextFormField, FormStrings.labelDeadlineDays);
        await tester.enterText(interval, '1,5');
        await tester.enterText(deadline, '4');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(form.data![FormModel.metaReminderIntervalSeconds], 129600);
        expect(form.deadlineDurationSeconds, 345600);
        await tester.enterText(deadline, '0');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(form.deadlineDurationSeconds, 0);
        await tester.enterText(interval, '');
        await tester.enterText(deadline, '');
        await tester
            .widget<EditorActionBar>(find.byType(EditorActionBar))
            .onSave();
        await tester.pumpAndSettle();
        expect(form.data!.containsKey(FormModel.metaReminderIntervalSeconds),
            isFalse);
        expect(form.deadlineDurationSeconds, isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
