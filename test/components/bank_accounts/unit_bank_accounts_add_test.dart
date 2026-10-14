import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var availability = 'empty';

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
          case '/rest/v1/rpc/get_current_organization_data':
            response = {'code': 403};
          case '/rest/v1/rpc/get_my_admin_bank_accounts':
            if (availability == 'failure') {
              return http.Response(
                '{"message":"fixture unavailable","code":"503"}',
                503,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            response = availability == 'available'
                ? [
                    {'id': 9, 'title': 'Available account', 'type': 'FIO'},
                  ]
                : [];
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

  for (final width in [1200.0, 400.0]) {
    for (final scenario in ['empty', 'available', 'failure']) {
      testWidgets(
        'bank add dialog handles $scenario under admin FAB ($width)',
        (tester) async {
          availability = scenario;
          await tester.binding.setSurfaceSize(Size(width, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          var previewOpened = false;
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [Locale('cs')],
              path: 'unused',
              startLocale: const Locale('cs'),
              assetLoader: _Translations(),
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
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
          expect(
            find.text(BankAccountStrings.createNewAccount),
            findsOneWidget,
          );
          final link = find.widgetWithText(
            TextButton,
            BankAccountStrings.linkExistingAccount,
          );
          final create = find.widgetWithText(
            TextButton,
            BankAccountStrings.createNewAccount,
          );
          expect(tester.widget<TextButton>(create).onPressed, isNotNull);
          expect(
            tester.widget<TextButton>(link).onPressed,
            scenario == 'available' ? isNotNull : isNull,
          );
          expect(
            find.text(CommonStrings.unexpectedError),
            scenario == 'failure' ? findsOneWidget : findsNothing,
          );
          if (scenario == 'failure') {
            availability = 'available';
            await tester.tap(
              find.widgetWithText(TextButton, CommonStrings.retry),
            );
            await tester.pumpAndSettle();
            expect(find.text(CommonStrings.unexpectedError), findsNothing);
            expect(tester.widget<TextButton>(link).onPressed, isNotNull);
          }
          if (scenario != 'empty') {
            await tester.tap(link);
            await tester.pumpAndSettle();
            expect(find.text(BankAccountStrings.selectAccount), findsOneWidget);
            expect(find.text('Available account'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
