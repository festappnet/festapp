import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:festapp_core/eshop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_connection_tab.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  for (final readOnly in [false, true]) {
    testWidgets(
      'last failure survives recovery and respects read-only UI: $readOnly',
      (tester) async {
        final token = TextEditingController();
        final account = BankAccountModel.fromJson({
          'id': 1,
          'is_admin': true,
          'bank_sync': {
            'state': 'connected',
            'mode': 'api',
            'bank_pull_at': '2026-11-01T22:33:04Z',
            'last_error': null,
            'last_failure': {
              'version': 1,
              'id': '046aec2a-c9ef-4d94-8b1c-7bcf319d345a',
              'occurred_at': '2026-11-01T22:33:04.123Z',
              'code': 'missing_statement_info',
              'stage': 'response_decode',
              'transport': 'proxy',
              'operation': 'transactions',
              'http_status': 200,
              'document_shape': 'object',
              'statement_shape': 'object',
              'info_shape': 'missing',
            },
          },
        });
        expect(
          BankAccountModel.fromJson(account.toJson())
              .bankSync!
              .lastFailure!
              .code,
          'missing_statement_info',
        );
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en')],
            startLocale: const Locale('en'),
            path: 'unused',
            assetLoader: const _Translations(),
            child: Builder(
              builder: (context) => MaterialApp(
                builder: DependencyMaterialBridge.builder,
                locale: context.locale,
                localizationsDelegates: [
                  ...context.localizationDelegates,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                supportedLocales: context.supportedLocales,
                home: Scaffold(
                  body: SingleChildScrollView(
                    child: BankAccountConnectionTab(
                      account: account,
                      isReadOnly: readOnly,
                      isFio: false,
                      isSaving: false,
                      pairingCode: null,
                      onRegenerateToken: () {},
                      tokenController: token,
                      expiryDate: null,
                      onExpiryDateChanged: (_) {},
                      onSaveToken: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (readOnly) {
          expect(find.text('Last recorded error'), findsNothing);
        } else {
          await tester.tap(find.text('Last recorded error'));
          await tester.pumpAndSettle();
          expect(
            find.text('The latest bank pull succeeded after this error.'),
            findsOneWidget,
          );
          expect(find.textContaining('accountStatement.info'), findsOneWidget);
          expect(find.byType(SelectableText), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        token.dispose();
      },
    );
  }
}
