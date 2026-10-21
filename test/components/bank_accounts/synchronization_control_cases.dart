import 'package:timezone/data/latest.dart' as timezone_data;
import '../../support/fixtures/rights_context_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_connection_tab.dart';

class _Translations extends AssetLoader {
  final Map<String, dynamic> data;
  const _Translations(this.data);
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    timezone_data.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
  });
  for (final scenario in [
    'paused-admin',
    'active-admin',
    'degraded-admin',
    'paused-reader',
    'paused-nonadmin',
    'paused-busy'
  ]) {
    testWidgets('synchronization switch: $scenario', (tester) async {
      await EasyLocalization.ensureInitialized();
      final translations =
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())
              as Map<String, dynamic>;
      final rights = RightsContextFixture.bankAccounts(
          manageableAccounts: scenario.endsWith('nonadmin') ? {} : {1});
      addTearDown(rights.dispose);
      bool? requested;
      final controller = TextEditingController();
      final paused = scenario.startsWith('paused');
      final busy = scenario.endsWith('busy');
      final account = BankAccountModel.fromJson({
        'id': 1,
        'is_admin': !scenario.endsWith('nonadmin'),
        'bank_sync': {
          'state': paused
              ? 'suspended'
              : scenario.startsWith('degraded')
                  ? 'degraded'
                  : 'connected',
          'mode': 'api'
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
                    isReadOnly: scenario.endsWith('reader'),
                    isFio: false,
                    isSaving: busy,
                    isChangingSynchronization: busy,
                    pairingCode: null,
                    onRegenerateToken: () {},
                    tokenController: controller,
                    expiryDate: null,
                    onExpiryDateChanged: (_) {},
                    onSaveToken: () {},
                    onSynchronizationChanged: (enabled) => requested = enabled,
                  )),
                )),
      ));
      await tester.pump();
      final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(toggle.value, !paused);
      final canEdit = !scenario.endsWith('reader') &&
          !scenario.endsWith('nonadmin') &&
          !busy;
      expect(toggle.onChanged != null, canEdit);
      if (canEdit) {
        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();
        expect(requested, paused);
      }
      if (busy) {
        expect(
            find.text(translations['BankAccount']['synchronizationChanging']),
            findsOneWidget);
        expect(find.text(translations['BankAccount']['tokenVerifying']),
            findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
