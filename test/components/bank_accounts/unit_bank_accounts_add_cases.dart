import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
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
          default:
            throw StateError('Unexpected request: ${request.url.path}');
        }
        return http.Response(jsonEncode(response), 200,
            headers: {'content-type': 'application/json'}, request: request);
      }),
    );
  });

  tearDownAll(() => Supabase.instance.dispose());

  for (final width in [1200.0, 400.0]) {
    testWidgets('empty bank list can add an account under admin FAB ($width)',
        (tester) async {
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
