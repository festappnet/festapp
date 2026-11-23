import 'package:fstapp/components/forms/supabase_form_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/eshop.dart';
import 'package:festapp_core/forms.dart';
import 'package:fstapp/components/forms/models/form_field_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'package:fstapp/components/forms/views/form_bank_account_picker.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync());
}

final _accounts = [
  BankAccountModel(id: 1, title: 'Main account', supportedCurrencies: ['CZK']),
  BankAccountModel(id: 2, title: 'Euro account', supportedCurrencies: ['EUR']),
  BankAccountModel(
    id: 3,
    title: 'Second account',
    supportedCurrencies: ['CZK', 'EUR'],
  ),
  BankAccountModel(
    id: 4,
    title: 'Cash',
    type: 'CASH',
    supportedCurrencies: ['CZK'],
  ),
];

Future<void> _pump(
  WidgetTester tester,
  FormEditorDraft form, {
  bool canEdit = true,
  Set<String>? currencies,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'unused',
      startLocale: const Locale('en'),
      assetLoader: _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          builder: DependencyMaterialBridge.builder,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: [
            ...context.localizationDelegates,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Scaffold(
            body: StatefulBuilder(
              key: ObjectKey(form),
              builder: (context, update) => FormBankAccountPicker(
                form: form,
                currencies: currencies ?? formBankTransferCurrencies(form),
                canEdit: canEdit,
                onChanged: () => update(() {}),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

FormEditorDraft _load({int? selected, bool bankEnabled = true}) =>
    FormEditBundle.fromData({
      'form': {
        'id': 7,
        'link': 'registration',
        'bank_account': selected,
        'data': {
          'payments': {'bankEnabled': bankEnabled},
        },
      },
      'form_fields': [],
      'product_types': [],
      'products': [],
      'available_bank_accounts': _accounts.map((a) => a.toJson()).toList(),
    }).form;

DropdownButton<String> _dropdown(WidgetTester tester) =>
    tester.widget<DropdownButton<String>>(
      find.byWidgetPredicate((w) => w is DropdownButton<String>),
    );

Future<void> _choose(WidgetTester tester, String text) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining(text).last);
  await tester.pumpAndSettle();
}

// Model the update_form_client_sync_v1 acknowledgement and use the same receipt
// parser as DbForms.updateForm, followed by the editor's RPC bundle loader.
Future<FormEditorDraft> _saveAndReload(
  FormEditorDraft draft,
  int? expected,
) async {
  final commands = SupabaseFormCommands.withTransport(
    ClientCommandTransport((operation, params) async {
      expect(operation, 'update_form_client_sync_v1');
      final saved = Map<String, dynamic>.from(params['p_form'] as Map);
      expect(saved.containsKey('bank_account'), isTrue);
      expect(saved['bank_account'], expected);
      // An unlinked ID would be rejected by update_form with 4020.
      expect(saved['bank_account'], isNot(99));
      return {
        'status': 'applied',
        'code': 200,
        'data': {
          'link': 'registration',
          'product_versions': <String, int>{},
          'product_type_versions': <String, int>{},
          'authoring': {
            'form': {
              'id': draft.definition.id,
              'data': draft.definition.data,
              'bank_account': saved['bank_account'],
              'aggregate_version': draft.aggregateVersion + 1,
            },
            'fields': [],
            'products': [],
            'productTypes': [],
            'productVersions': <String, int>{},
            'productTypeVersions': <String, int>{},
          },
        },
        'mutation': {
          'commandId': params['p_command_id'],
          'receiptId': params['p_command_id'],
          'commitId': null,
          'replayed': false,
          'occurredAt': '2026-11-22T12:00:00Z',
        },
        'sync': {'replacements': <Object>[]},
      };
    }),
  );
  final response = await commands.save(draft.toEditedJson());
  final acknowledged = FormEditBundle.fromSave(draft, response).form;
  expect(acknowledged.aggregateVersion, draft.aggregateVersion + 1);
  expect(acknowledged.definition.bankAccountId, expected);
  expect(acknowledged.bankAccount?.id, expected);
  final reloaded = _load(selected: acknowledged.definition.bankAccountId);
  expect(reloaded.toEditedJson()['bank_account'], expected);
  return reloaded;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('picker offers inherited and currency eligible accounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
    const longTitle =
        'Second account for the association of local dance clubs and volunteers';
    final form = _load()
      ..availableBankAccounts = [
        ..._accounts.where((account) => account.id != 3),
        BankAccountModel(
          id: 3,
          title: longTitle,
          supportedCurrencies: ['CZK', 'EUR'],
        ),
      ];
    await _pump(tester, form, currencies: {'CZK'});
    expect(_dropdown(tester).items!.map((i) => i.value), ['default', '1', '3']);
    expect(find.text(BankAccountStrings.formAccountDefaultPlain), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final option = find.textContaining(longTitle).last;
    expect(tester.widget<Text>(option).maxLines, isNull);
    expect(tester.getSize(option).height, greaterThan(kMinInteractiveDimension));
    await tester.tap(option);
    await tester.pumpAndSettle();
    expect(form.definition.bankAccountId, 3);
    expect(form.bankAccount?.id, 3);
    expect(_dropdown(tester).value, '3');
    await _choose(tester, 'By organization order');
    expect(form.definition.bankAccountId, isNull);
    expect(form.bankAccount, isNull);
    expect(form.toEditedJson().containsKey('bank_account'), isTrue);
    expect(form.toEditedJson()['bank_account'], isNull);
    expect(_dropdown(tester).value, 'default');
  });

  testWidgets(
    'currency eligibility ignores hidden and free products and trims codes',
    (tester) async {
      final form = _load(selected: 1);
      form.relatedFields = [
        FormFieldDraft.fromDefinition(
          FormFieldDefinition(
            isHidden: true,
            productType: ProductTypeModel(
              products: [ProductModel(price: 20, currencyCode: 'EUR')],
            ),
          ),
        ),
        FormFieldDraft.fromDefinition(
          FormFieldDefinition(
            productType: ProductTypeModel(
              products: [
                ProductModel(price: 20, currencyCode: ' CZK '),
                ProductModel(price: 20, currencyCode: 'EUR', isHidden: true),
                ProductModel(price: 0, currencyCode: 'EUR'),
                ProductModel(price: -1, currencyCode: 'EUR'),
                ProductModel(currencyCode: 'EUR'),
                ProductModel(price: 20, currencyCode: '  '),
                ProductModel(price: 20),
              ],
            ),
          ),
        ),
      ];
      expect(formBankTransferCurrencies(form), {'CZK'});
      await _pump(tester, form);
      expect(_dropdown(tester).items!.map((i) => i.value), [
        'default',
        '1',
        '3',
      ]);
      expect(find.textContaining('Selected account unavailable'), findsNothing);
      await _pump(tester, _load(), currencies: {'CZK', 'EUR'});
      expect(_dropdown(tester).items!.map((i) => i.value), ['default', '3']);
      expect(
        formBankTransferAccounts(form, {'CZK', 'EUR'}).map(
          (currency, account) => MapEntry(currency, account?.id),
        ),
        {'CZK': 1, 'EUR': 2},
      );
      expect(
        formBankTransferAccounts(form, {'CZK', 'EUR'}, accountId: 1).map(
          (currency, account) => MapEntry(currency, account?.id),
        ),
        {'CZK': 1, 'EUR': null},
      );
    },
  );

  testWidgets('unavailable account uses its label or ID fallback', (
    tester,
  ) async {
    for (final id in [2, 99]) {
      final form = _load(selected: id);
      await _pump(tester, form, currencies: {'CZK'});
      expect(
        find.text(
          BankAccountStrings.formAccountUnavailable(
            id == 2 ? 'Euro account' : 'ID 99',
          ),
        ),
        findsOneWidget,
      );
      expect(form.toEditedJson()['bank_account'], id == 2 ? 2 : null);
    }
    final form = _load(selected: 5);
    form.availableBankAccounts = [
      BankAccountModel(id: 5, supportedCurrencies: ['EUR']),
    ];
    await _pump(tester, form, currencies: {'CZK'});
    expect(
      find.text(BankAccountStrings.formAccountUnavailable('ID 5')),
      findsOneWidget,
    );
  });

  testWidgets('read only picker cannot change the account', (tester) async {
    final form = _load(selected: 1);
    await _pump(tester, form, canEdit: false, currencies: {'CZK'});
    expect(_dropdown(tester).onChanged, isNull);
    expect(form.toEditedJson()['bank_account'], 1);
  });

  testWidgets('empty currencies show plain organization order', (tester) async {
    await _pump(tester, _load());
    expect(find.text('By organization order'), findsOneWidget);
    expect(find.textContaining('currently:'), findsNothing);
  });

  testWidgets(
    'explicit selection and NULL survive production save parsing and reload',
    (tester) async {
      var form = _load(selected: 1);
      await _pump(tester, form, currencies: {'CZK'});
      await _choose(tester, 'Second account');
      form = await _saveAndReload(form, 3);
      await _pump(tester, form, currencies: {'CZK'});
      expect(_dropdown(tester).value, '3');
      await _choose(tester, 'By organization order');
      form = await _saveAndReload(form, null);
      await _pump(tester, form, currencies: {'CZK'});
      expect(_dropdown(tester).value, 'default');
      await _choose(tester, 'Second account');
      // Discard replaces the draft, just like the production ObjectKey(_form).
      await _pump(tester, _load(), currencies: {'CZK'});
      expect(_dropdown(tester).value, 'default');
    },
  );

  test(
    'unchanged unlinked account saves as NULL even with bank payments disabled',
    () async {
      for (final bankEnabled in [true, false]) {
        final form = _load(selected: 99, bankEnabled: bankEnabled);
        expect(form.definition.bankAccountId, 99);
        expect(form.bankAccount, isNull);
        expect(form.toEditedJson()['bank_account'], isNull);
        await _saveAndReload(form, null);
      }
    },
  );
}
