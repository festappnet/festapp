import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_account_card.dart';

import '../../support/fixtures/rights_context_fixture.dart';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/time.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/views/unit_bank_accounts_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

bool _includeAccount = false;
List<Map<String, Object>>? _bankAccounts;
bool _failBank = false;
bool _failOrganization = false;
int _bankRequests = 0;
int _organizationRequests = 0;

Widget _screen() => EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'unused',
      startLocale: const Locale('cs'),
      assetLoader: _Translations(),
      child: Builder(
          builder: (context) => MaterialApp(builder: DependencyMaterialBridge.builder,
                locale: context.locale,
                localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
                supportedLocales: context.supportedLocales,
                home: const UnitBankAccountsScreen(unitId: 1),
              )),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    OccasionTimeContext.initializeTimeZones();
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
            _bankRequests++;
            if (_failBank) {
              return http.Response(
                jsonEncode({'code': '21000', 'message': 'private SQL failure'}),
                500,
                headers: {'content-type': 'application/json'},
              );
            }
            response = _bankAccounts ?? (_includeAccount
                ? [
                    {
                      'id': 12,
                      'title': 'Fixture account',
                      'type': 'FIO',
                      'supported_currencies': ['CZK'],
                      'is_admin': false
                    }
                  ]
                : []);
          case '/rest/v1/rpc/get_linkable_bank_accounts':
            response = [];
          case '/rest/v1/rpc/get_current_organization_data':
            _organizationRequests++;
            if (_failOrganization) {
              return http.Response(
                jsonEncode({'code': '21000', 'message': 'private SQL failure'}),
                500,
                headers: {'content-type': 'application/json'},
              );
            }
            response = {'code': 403};
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
        return http.Response(jsonEncode(response), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  setUp(() {
    _includeAccount = false;
    _bankAccounts = null;
    _failBank = false;
    _failOrganization = false;
    _bankRequests = 0;
    _organizationRequests = 0;
  });

  testWidgets('organization failure keeps accounts and retries only context',
      (tester) async {
    _includeAccount = true;
    _failOrganization = true;
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    expect(find.text('Fixture account'), findsOneWidget);
    expect(find.textContaining('private SQL'), findsNothing);
    expect(find.text(CommonStrings.retry), findsOneWidget);
    _failOrganization = false;
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();
    expect(_bankRequests, 1);
    expect(_organizationRequests, 2);
    expect(find.text(CommonStrings.retry), findsNothing);
    expect(find.text('Fixture account'), findsOneWidget);
  });

  testWidgets('account failure can retry without raw SQL dialog',
      (tester) async {
    _includeAccount = true;
    _failBank = true;
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('private SQL'), findsNothing);
    expect(find.text(CommonStrings.retry), findsOneWidget);
    _failBank = false;
    await tester.tap(find.text(CommonStrings.retry));
    await tester.pumpAndSettle();
    expect(_bankRequests, 2);
    expect(find.text('Fixture account'), findsOneWidget);
    expect(find.text(CommonStrings.retry), findsNothing);
  });

  testWidgets('management order and per-currency defaults survive reopening',
      (tester) async {
    final rights = RightsContextFixture.bankAccounts(unitId: 1, canManageUnit: true);
    addTearDown(rights.dispose);
    _bankAccounts = [
      {
        'id': 35,
        'priority': 0,
        'title': 'Účet pro vstupenky',
        'type': 'FIO',
        'supported_currencies': ['CZK', 'EUR'],
      },
      {
        'id': 12,
        'priority': 1,
        'title': 'Účet pro zahraniční platby',
        'type': 'FIO',
        'supported_currencies': ['EUR', 'PLN'],
      },
    ];
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    void expectOrder(List<int> order, List<Set<String>> currencies) {
      final cards = tester.widgetList<UnitBankAccountCard>(
        find.byType(UnitBankAccountCard),
      );
      expect(cards.map((card) => card.account.id), order);
      expect(cards.map((card) => card.primaryCurrencies), currencies);
    }
    expectOrder([35, 12], [{'CZK', 'EUR'}, {'PLN'}]);

    _bankAccounts = [
      {..._bankAccounts![1], 'priority': 0},
      {..._bankAccounts![0], 'priority': 1},
    ];
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();
    expect(_bankRequests, 2);
    expectOrder([12, 35], [{'EUR', 'PLN'}, {'CZK'}]);
  });

  for (final width in [1200.0, 400.0]) {
    testWidgets('empty bank list can add an account under admin FAB ($width)',
        (tester) async {
      final rights = RightsContextFixture.bankAccounts(unitId: 1, canManageUnit: true);
      addTearDown(rights.dispose);
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var previewOpened = false;
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('cs')],
        path: 'unused',
        startLocale: const Locale('cs'),
        assetLoader: _Translations(),
        child: Builder(
          builder: (context) => MaterialApp(builder: DependencyMaterialBridge.builder,
            locale: context.locale,
            localizationsDelegates: [...context.localizationDelegates, ...GlobalMaterialLocalizations.delegates],
            supportedLocales: context.supportedLocales,
            home: Scaffold(
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
        ),
      ));
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
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
