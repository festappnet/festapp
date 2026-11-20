import 'package:fstapp/widgets/dependency_material_bridge.dart';

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_general_tab.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_accounts_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fixtures/client_command_response_fixture.dart';
import '../../support/fixtures/local_storage_fixture.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

Widget _localized(Widget home) => EasyLocalization(
  supportedLocales: const [Locale('cs')],
  path: 'unused',
  startLocale: const Locale('cs'),
  assetLoader: _Translations(),
  child: Builder(
    builder: (context) => MaterialApp(
      builder: DependencyMaterialBridge.builder,
      locale: context.locale,
      localizationsDelegates: [
        ...context.localizationDelegates,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: context.supportedLocales,
      home: home,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  registerLocalStorageFixture();
  Map<String, dynamic>? savedPayload;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final Object response;
        switch (request.url.path) {
          case '/rest/v1/rpc/get_bank_accounts_for_unit_management':
            response = [];
          case '/rest/v1/rpc/manage_bank_authoring':
            final command = jsonDecode(request.body) as Map<String, dynamic>;
            expect(command['p_action'], 'save');
            savedPayload = command['p_payload'] as Map<String, dynamic>;
            response = commandResponseFixture(
              command['p_command_id'] as String,
              data: {'accountId': 47},
            );
          case '/rest/v1/rpc/get_current_organization_data':
            response = {'code': 403};
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  setUp(() => savedPayload = null);

  Future<void> openNewAccount(
    WidgetTester tester, {
    ValueChanged<BankAccountModel>? onUpdated,
  }) async {
    const toastChannel = MethodChannel('PonnamKarthik/fluttertoast');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(toastChannel, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(toastChannel, null));
    await tester.pumpWidget(
      _localized(
        BankAccountSettingsScreen(
          unitId: 1,
          account: BankAccountModel(id: 0, title: 'Bratislava'),
          onUpdated: onUpdated,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final national = find.byKey(const ValueKey('bank-account-national'));
  final bankCode = find.byKey(const ValueKey('bank-account-bank-code'));
  final iban = find.byKey(const ValueKey('bank-account-iban'));
  Finder saveButton() =>
      find.widgetWithText(ElevatedButton, BankAccountStrings.saveChanges);
  String fieldText(WidgetTester tester, Finder finder) =>
      tester.widget<TextFormField>(finder).controller!.text;

  Future<void> saveValidAccount(WidgetTester tester) async {
    final save = saveButton();
    await tester.ensureVisible(save);
    // The durable command journal performs real filesystem I/O.
    final submit =
        tester.widget<ElevatedButton>(save).onPressed!
            as Future<void> Function();
    await tester.runAsync(submit);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Slovak domestic entry keeps country drafts, validates and reopens',
    (tester) async {
      BankAccountModel? updated;
      await openNewAccount(tester, onUpdated: (account) => updated = account);
      await tester.enterText(national, '19-20001457/0800');
      final slovak = find.text(BankAccountStrings.inputModeSlovak);
      await tester.tap(slovak);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(Chip, 'EUR'), findsOneWidget);
      expect(fieldText(tester, national), isEmpty);
      expect(fieldText(tester, bankCode), isEmpty);

      await tester.enterText(national, '289-1987426353 / 0720');
      expect(fieldText(tester, national), '289-1987426353');
      expect(fieldText(tester, bankCode), '0720');
      await tester.tap(find.byTooltip(BankAccountStrings.bankCodeLabel));
      await tester.pumpAndSettle();
      final tatra = find.textContaining(
        RegExp(r'^1100.*Tatra banka', caseSensitive: false),
      );
      await tester.ensureVisible(tatra);
      await tester.tap(tatra);
      await tester.pumpAndSettle();
      expect(fieldText(tester, bankCode), '1100');
      await tester.enterText(national, '1234567-1');
      await tester.enterText(bankCode, '12');
      await tester.ensureVisible(saveButton());
      await tester.tap(saveButton());
      await tester.pumpAndSettle();
      expect(tester.state<FormFieldState<String>>(national).hasError, isTrue);
      expect(tester.state<FormFieldState<String>>(bankCode).hasError, isTrue);
      expect(savedPayload, isNull);

      await tester.enterText(national, '289-1987426353/0720');
      final czech = find.text(BankAccountStrings.inputModeSplit);
      await tester.ensureVisible(czech);
      await tester.tap(czech);
      await tester.pumpAndSettle();
      expect(fieldText(tester, national), '19-20001457');
      expect(fieldText(tester, bankCode), '0800');
      await tester.tap(slovak);
      await tester.pumpAndSettle();
      expect(fieldText(tester, national), '289-1987426353');
      expect(fieldText(tester, bankCode), '0720');
      await saveValidAccount(tester);
      expect(savedPayload?['accountNumber'], 'SK6807200002891987426353');
      expect(savedPayload?['displayNumber'], isNull);
      expect(savedPayload?['currencies'], ['EUR']);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _localized(
          BankAccountSettingsScreen(
            unitId: 1,
            account: updated!,
            readOnly: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BankAccountGeneralTab>(find.byType(BankAccountGeneralTab))
            .inputMode,
        BankAccountInputMode.slovak,
      );
      expect(fieldText(tester, national), '289-1987426353');
      expect(fieldText(tester, bankCode), '0720');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('IBAN entry validates and saves a formatted Slovak IBAN', (
    tester,
  ) async {
    await openNewAccount(tester);
    await tester.tap(find.text(BankAccountStrings.inputModeIban));
    await tester.pumpAndSettle();
    await tester.enterText(iban, 'SK3212000000198742637541');
    await tester.ensureVisible(saveButton());
    await tester.tap(saveButton());
    await tester.pumpAndSettle();
    expect(tester.state<FormFieldState<String>>(iban).hasError, isTrue);
    expect(savedPayload, isNull);
    await tester.enterText(iban, 'sk31 1200 0000 1987 4263 7541');
    await saveValidAccount(tester);
    expect(savedPayload?['accountNumber'], 'SK3112000000198742637541');
    expect(savedPayload?['displayNumber'], isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching to Slovakia preserves manually selected currencies', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localized(
        BankAccountSettingsScreen(unitId: 1, account: BankAccountModel(id: 0)),
      ),
    );
    await tester.pumpAndSettle();
    final addCurrency = find.widgetWithText(
      ActionChip,
      BankAccountStrings.addCurrency,
    );
    await tester.ensureVisible(addCurrency);
    await tester.tap(addCurrency);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'EUR'));
    await tester.pumpAndSettle();
    final slovak = find.text(BankAccountStrings.inputModeSlovak);
    await tester.ensureVisible(slovak);
    await tester.tap(slovak);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Chip, 'CZK'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'EUR'), findsOneWidget);
  });

  for (final width in [1200.0, 400.0]) {
    testWidgets('empty bank list can add an account under admin FAB ($width)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var previewOpened = false;
      await tester.pumpWidget(
        _localized(
          Scaffold(
            appBar: AppBar(title: const Text('Administration')),
            body: const Padding(
              padding: EdgeInsets.only(left: 60),
              child: UnitBankAccountsScreen(unitId: 1),
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () => previewOpened = true,
              child: const Icon(Icons.remove_red_eye_rounded),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The outer admin preview must not intercept the account creation action.
      expect(find.text(BankAccountStrings.description), findsOneWidget);
      final addButton = find.ancestor(
        of: find.byIcon(Icons.add),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ButtonStyleButton || widget is FloatingActionButton,
        ),
      );
      expect(addButton.hitTestable(), findsOneWidget);
      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(previewOpened, isFalse);
      expect(find.text(BankAccountStrings.createNewAccount), findsOneWidget);
      expect(find.text(BankAccountStrings.linkExistingAccount), findsOneWidget);

      await tester.tap(find.text(BankAccountStrings.createNewAccount));
      await tester.pumpAndSettle();
      final national = find.byKey(const ValueKey('bank-account-national'));
      final iban = find.byKey(const ValueKey('bank-account-iban'));
      final bankCode = find.byKey(const ValueKey('bank-account-bank-code'));
      final slash = find.text('/');
      expect(
        tester.getRect(national).right,
        lessThan(tester.getRect(slash).left),
      );
      expect(
        tester.getRect(slash).right,
        lessThan(tester.getRect(bankCode).left),
      );
      await tester.enterText(national, '19-20001457 / 0800');
      await tester.pump();
      expect(find.text('Česká spořitelna, a.s.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(national).controller!.text,
        '19-20001457',
      );
      expect(tester.widget<TextFormField>(bankCode).controller!.text, '0800');

      await tester.tap(find.text(BankAccountStrings.inputModeIban));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(iban).controller!.text,
        'CZ6008000000190020001457',
      );

      await tester.tap(find.text(BankAccountStrings.inputModeSplit));
      await tester.pumpAndSettle();
      await tester.enterText(bankCode, '9999');
      final save = find.text(BankAccountStrings.saveChanges);
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text(CommonStrings.invalidFormat), findsOneWidget);

      await tester.tap(find.text(BankAccountStrings.inputModeIban));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(iban).controller!.text, isEmpty);

      await tester.tap(find.text(BankAccountStrings.inputModeSplit));
      await tester.pumpAndSettle();
      final bankPicker = find.byTooltip(BankAccountStrings.bankCodeLabel);
      await tester.tap(bankPicker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0800 · Česká spořitelna, a.s.'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(national).controller!.text,
        '19-20001457',
      );
      expect(tester.widget<TextFormField>(bankCode).controller!.text, '0800');

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
