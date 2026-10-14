import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_connection_tab.dart';

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  testWidgets(
      'active connection refreshes bank facts, hidden or disposed panel does not poll',
      (tester) async {
    await EasyLocalization.ensureInitialized();
    final token = TextEditingController();
    var refreshes = 0;
    var active = true;
    late StateSetter update;
    var account = BankAccountModel.fromJson({
      'id': 1,
      'is_admin': true,
      'bank_sync': {'state': 'connected', 'mode': 'api'}
    });
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'unused',
      startLocale: const Locale('en'),
      assetLoader: const _Translations(),
      child: Builder(
          builder: (context) => MaterialApp(
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                home: Scaffold(
                    body: StatefulBuilder(builder: (context, setState) {
                  update = setState;
                  return TickerMode(
                      enabled: active,
                      child: BankAccountConnectionTab(
                        account: account,
                        isReadOnly: false,
                        isFio: false,
                        isSaving: false,
                        pairingCode: null,
                        onRegenerateToken: () {},
                        tokenController: token,
                        expiryDate: null,
                        onExpiryDateChanged: (_) {},
                        onSaveToken: () {},
                        onRefreshConnection: () async {
                          refreshes++;
                          setState(() => account = account.copyWith(
                                  bankSync: BankSyncConnection.fromJson({
                                'state': 'connected',
                                'mode': 'api',
                                'bank_pull_at':
                                    DateTime.now().toUtc().toIso8601String(),
                              })));
                        },
                      ));
                })),
              )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Not received yet'), findsNWidgets(2));
    await tester.pump(const Duration(minutes: 1));
    await tester.pump();
    expect(refreshes, 1);
    expect(find.text('Not received yet'), findsOneWidget);
    update(() => active = false);
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(refreshes, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
    expect(refreshes, 1);
    token.dispose();
  });
}
