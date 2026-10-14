import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_connection_tab.dart';

class _Translations extends AssetLoader {
  final Map<String, dynamic> data;
  const _Translations(this.data);
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  for (final bank in ['2010', '3030', '0800']) {
    testWidgets('email connection availability for bank $bank', (tester) async {
      await EasyLocalization.ensureInitialized();
      final data =
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>;
      final token = TextEditingController();
      var calls = 0;
      await tester.pumpWidget(EasyLocalization(
          supportedLocales: const [Locale('cs')],
          path: 'unused',
          startLocale: const Locale('cs'),
          assetLoader: _Translations(data),
          child: Builder(
              builder: (context) => MaterialApp(
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  home: Scaffold(
                      body: BankAccountConnectionTab(
                    account: BankAccountModel(
                        id: 1,
                        type: 'OTHER',
                        accountNumber: 'CZ00 $bank 0000 0000 0000 0000'),
                    isReadOnly: false,
                    isFio: false,
                    isSaving: false,
                    pairingCode: null,
                    onConnectEmail: () => calls++,
                    onRegenerateToken: () {},
                    tokenController: token,
                    expiryDate: null,
                    onExpiryDateChanged: (_) {},
                    onSaveToken: () {},
                  ))))));
      await tester.pumpAndSettle();
      final button = find.widgetWithText(
          OutlinedButton, data['BankAccount']['connect_email']);
      expect(tester.widget<OutlinedButton>(button).onPressed == null,
          bank == '0800');
      if (bank == '0800') {
        expect(find.text(data['BankAccount']['emailBankUnsupported']),
            findsOneWidget);
      } else {
        await tester.tap(button);
        expect(calls, 1);
        expect(find.text(data['BankAccount']['emailBankUnsupported']),
            findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      token.dispose();
    });
  }
  for (final saving in [false, true]) {
    testWidgets(
        'token verification shows accurate state and bounded progress (saving=$saving)',
        (tester) async {
      await EasyLocalization.ensureInitialized();
      final translations =
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>;
      final controller = TextEditingController();
      final account = BankAccountModel.fromJson({
        'id': 159,
        'type': 'FIO',
        'token_masked': 'old-stale-token',
        'bank_sync': {
          'state': 'degraded',
          'mode': 'api',
          'last_error': 'fio_token_invalid_or_inactive',
          'token_masked': 'current********'
        }
      });
      await tester.pumpWidget(EasyLocalization(
          supportedLocales: const [Locale('cs')],
          path: 'unused',
          startLocale: const Locale('cs'),
          assetLoader: _Translations(translations),
          child: Builder(
              builder: (context) => MaterialApp(
                  locale: context.locale,
                  localizationsDelegates: context.localizationDelegates,
                  supportedLocales: context.supportedLocales,
                  home: Scaffold(
                      body: BankAccountConnectionTab(
                          account: account,
                          isReadOnly: false,
                          isFio: true,
                          isSaving: saving,
                          pairingCode: null,
                          onRegenerateToken: () {},
                          tokenController: controller,
                          expiryDate: null,
                          onExpiryDateChanged: (_) {},
                          onSaveToken: () {}))))));
      if (saving) {
        await tester.pump(const Duration(milliseconds: 100));
      } else {
        await tester.pumpAndSettle();
      }
      expect(find.text(translations['BankAccount']['fioTokenInactive']),
          saving ? findsNothing : findsOneWidget);
      if (saving) {
        expect(find.text(translations['BankAccount']['tokenVerificationWait']),
            findsOneWidget);
        expect(tester.getSize(find.byType(CircularProgressIndicator)),
            const Size(20, 20));
        expect(tester.takeException(), isNull);
      } else {
        expect(find.textContaining('Vyžaduje pozornost'), findsOneWidget);
      }
      expect(find.textContaining('current********'), findsOneWidget);
      expect(find.textContaining('old-stale-token'), findsNothing);
      expect(find.text('fio_token_invalid_or_inactive'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
