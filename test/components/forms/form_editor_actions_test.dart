import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/forms/views/form_design_content.dart';
import 'package:fstapp/components/forms/views/form_settings_content.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/features/form_feature.dart';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/forms/models/form_field_model.dart';
import 'package:fstapp/components/_shared/editor_action_bar.dart';
import 'package:fstapp/components/forms/views/form_editor_content.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';

void main() {
  setUpAll(() {
    Localization.load(const Locale('cs'),
        translations: Translations(
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>));
  });
  for (final canManage in [true, false]) {
    for (final hasCzkAccount in [true, false]) {
      testWidgets(
          'bank guidance handles missing currencies and access ($canManage, $hasCzkAccount)',
          (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
          unit: UnitModel(id: 5),
          unitUser: OccasionUserModel(isEditor: canManage),
          occasionUser: OccasionUserModel(isEditor: true),
          occasion: OccasionModel(
              isOpen: true,
              isHidden: false,
              isPromoted: false,
              features: [FormFeature(code: 'form')]),
        );
        addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
        final accounts = hasCzkAccount
            ? [
                BankAccountModel(
                    id: 1, title: 'CZK account', supportedCurrencies: ['CZK'])
              ]
            : <BankAccountModel>[];
        final field = FormFieldModel(
            productType: ProductTypeModel(products: [
          ProductModel(currencyCode: 'CZK'),
          ProductModel(currencyCode: 'EUR')
        ]));
        await tester.pumpWidget(MaterialApp(
            home: FormSettingsContent(
          formLink: 'test',
          loadBundle: (_) async => FormEditBundle(
            form: FormModel(
                link: 'test',
                relatedFields: [field],
                availableBankAccounts: accounts,
                data: {}),
            formFields: [field],
            productTypes: [],
            products: [],
            availableBankAccounts: accounts,
          ),
        )));
        await tester.pumpAndSettle();
        expect(
            find.text(BankAccountStrings.missingAccountForCurrencies(
                hasCzkAccount ? 'EUR' : 'CZK, EUR')),
            findsOneWidget);
        expect(
            find.text(canManage
                ? BankAccountStrings.addAccountForPayments
                : BankAccountStrings.askManagerForPaymentAccount),
            findsOneWidget);
        expect(
            find.widgetWithText(
                TextButton, BankAccountStrings.manageInSettings),
            canManage ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  testWidgets('failed loading leaves the spinner and retry recovers',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: FormEditorContent(
            formLink: 'test',
            loadBundle: (_) async {
              calls++;
              if (calls == 1) return null;
              return FormEditBundle(
                  form: FormModel(link: 'test', data: {}),
                  formFields: [],
                  productTypes: [],
                  products: [],
                  availableBankAccounts: []);
            })));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Common.retry'.tr()), findsOneWidget);
    await tester.tap(find.text('Common.retry'.tr()));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Common.retry'.tr()), findsNothing);
    expect(find.byType(EditorActionBar), findsOneWidget);
  });
  testWidgets(
      'cancel in an embedded form must not remove the administration route',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(occasionUser: OccasionUserModel(isEditorOrder: true));
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = null);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Scaffold(body: Text('home'))));
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => FormEditorContent(
            formLink: 'test',
            loadBundle: (_) async => FormEditBundle(
                form: FormModel(link: 'test', relatedFields: [
                  FormFieldModel(
                      id: 5, title: 'Original title', type: 'text', data: {})
                ], data: {}),
                formFields: [],
                productTypes: [],
                products: [],
                availableBankAccounts: []))));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    final field = find.widgetWithText(TextFormField, 'Original title');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Changed title');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Changed title'), 'Original title');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Original title'), 'Changed title');
    await tester.pumpAndSettle();
    final discard = find.descendant(
        of: find.byType(EditorActionBar), matching: find.byType(TextButton));
    await tester.tap(discard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Common.keepEditing'.tr()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Changed title'), findsOneWidget);
    await tester.tap(discard);
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Common.discardChanges'.tr()));
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(TextFormField, 'Original title'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(find.byType(FormEditorContent), findsOneWidget);
  });
  for (final design in [true, false]) {
    testWidgets(
        '${design ? "design" : "settings"} discard restores data without closing the tab',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
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
      var closes = 0;
      Future<FormEditBundle?> load(String _) async => FormEditBundle(
          form: FormModel(
              link: 'test',
              title: 'Original title',
              relatedFields: [],
              data: {
                'design': <String, dynamic>{
                  'primary_color': '#336699',
                  'secondary_color': '#112233'
                }
              }),
          formFields: [],
          productTypes: [],
          products: [],
          availableBankAccounts: []);
      await tester.pumpWidget(MaterialApp(
          home: design
              ? FormDesignContent(
                  formLink: 'test',
                  loadBundle: load,
                  onActionCompleted: () => closes++)
              : FormSettingsContent(
                  formLink: 'test',
                  loadBundle: load,
                  onActionCompleted: () => closes++)));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Common.save'.tr());
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      Future<void> edit() async {
        if (design) {
          await tester.tap(find.byType(SwitchListTile).first);
        } else {
          await tester.enterText(
              find.widgetWithText(TextFormField, 'Original title'),
              'Changed title');
        }
        await tester.pumpAndSettle();
      }

      await edit();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      if (design) {
        await edit();
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await edit();
      }
      await tester.tap(find.descendant(
          of: find.byType(EditorActionBar), matching: find.byType(TextButton)));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, 'Common.discardChanges'.tr()));
      await tester.pumpAndSettle();
      expect(closes, 0);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      if (design) {
        expect(
            tester
                .widget<SwitchListTile>(find.byType(SwitchListTile).first)
                .value,
            false);
      } else {
        expect(find.widgetWithText(TextFormField, 'Original title'),
            findsOneWidget);
      }
    });
  }
}
