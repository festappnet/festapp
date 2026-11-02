import 'package:fstapp/widgets/app_dialog.dart';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:festapp_core/time.dart' as timezone_data;

import '../../support/fixtures/rights_context_fixture.dart';

import 'package:flutter/gestures.dart';
import 'package:url_launcher/link.dart';
import 'package:fstapp/components/bank_accounts/views/bank_sync_warning_button.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_navigation_page.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:http/http.dart' as http;

import '../../support/fixtures/root_supabase_fixture.dart';

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_sync_status.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/views/order_bank_sync_warning.dart';

class _WarningRouter extends RootStackRouter {
  final Widget home;
  _WarningRouter(this.home);

  @override
  List<AutoRoute> get routes => [
    AutoRoute(
      page: PageInfo('WarningHost', builder: (_) => home),
      path: '/',
    ),
    AutoRoute(
      page: PageInfo(
        BankAccountConnectionSettingsRoute.name,
        builder: (data) => Scaffold(
          body: Text(
            'Connection ${data.inheritedPathParams.getString('accountId')}',
          ),
        ),
      ),
      path: '/bank-accounts/:accountId/connection',
    ),
  ];
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/en.json').readAsStringSync());
}

void main() {
  setUpAll(() async {
    timezone_data.OccasionTimeContext.initializeTimeZones();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  PaymentInfoModel payment({double paid = 0, bool warning = true}) =>
      PaymentInfoModel.fromJson({
        'bank_account': 42,
        'amount': 100,
        'paid': paid,
        if (warning)
          'bank_sync_warning': {
            'code': 'suspended',
            'bank_account_title': 'Festival account',
            'contacts': [
              {'name': 'Jane Admin', 'email': 'admin@example.test'},
            ],
          },
      });

  test('parses optional operational warning and safe contact data', () {
    expect(payment(warning: false).bankSyncWarning, isNull);
    final warning = payment().bankSyncWarning!;
    expect(warning.code, 'suspended');
    expect(warning.bankAccountTitle, 'Festival account');
    expect(warning.contacts.single.name, 'Jane Admin');
    expect(warning.contacts.single.email, 'admin@example.test');
    expect(BankSyncWarning.fromJson({'code': 'stale'}).contacts, isEmpty);
    expect(
      BankSyncWarning.fromJson({
        'contacts': [
          {'name': 'Admin'},
        ],
      }).contacts.single.email,
      isNull,
    );
  });

  for (final status in [
    'connected',
    'suspended',
    'degraded',
    'unconfigured',
    'stale',
    'token_invalid',
    'account_mismatch',
    'connection_disabled',
    'temporary_failure',
    'unavailable',
    'token_missing',
    'email_missing',
    'healthy-form-projection',
    'missing-status',
    'pending-retry',
    'future-state',
    'CASH',
  ]) {
    testWidgets('account card status: $status', (tester) async {
      await EasyLocalization.ensureInitialized();
      final problem = [
        'suspended',
        'degraded',
        'unconfigured',
        'stale',
        'token_invalid',
        'account_mismatch',
        'connection_disabled',
        'temporary_failure',
        'unavailable',
        'token_missing',
        'email_missing',
      ].contains(status);
      final account = BankAccountModel.fromJson({
        'id': 42,
        'title': 'Festival account',
        'is_admin': false,
        'type': status == 'CASH' ? 'CASH' : 'FIO',
        if ([
          'connected',
          'suspended',
          'degraded',
          'future-state',
          'pending-retry',
          'CASH',
        ].contains(status))
          'bank_sync': {
            'state': status == 'pending-retry' ? 'degraded' : status,
            'mode': 'api',
            if (status == 'pending-retry') 'warning_pending': true,
          },
        // Form payment options deliberately expose only the safe warning,
        // without bank_sync connection details. Null means no known problem.
        if (status == 'healthy-form-projection') 'bank_sync_warning': null,
        if (problem)
          'bank_sync_warning': {
            'code': switch (status) {
              'suspended' => 'suspended',
              'degraded' => 'bank_error',
              'unconfigured' => 'not_configured',
              _ => status,
            },
            'bank_account_title': 'Festival account',
            'contacts': [
              {'name': 'Jane Admin', 'email': 'admin@example.test'},
            ],
          },
      });
      expect(
        BankAccountModel.fromJson(account.toJson()).bankSyncWarning?.code,
        account.bankSyncWarning?.code,
      );
      expect(
        account.copyWith(title: 'Renamed').bankSyncWarning?.code,
        account.bankSyncWarning?.code,
      );
      expect(
        account
            .copyWith(
              bankSync: BankSyncConnection.fromJson({
                'state': 'connected',
                'mode': 'api',
              }),
            )
            .bankSyncWarning,
        isNull,
      );
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'unused',
          startLocale: const Locale('en'),
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
                body: SizedBox(
                  width: 276,
                  child: BankAccountSyncStatus(account: account),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byIcon(Icons.check_circle_outline),
        status == 'connected' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byIcon(Icons.warning_amber_rounded),
        problem ? findsOneWidget : findsNothing,
      );
      if (!problem && status != 'connected') {
        expect(find.byType(Text), findsNothing);
      }
      if (status == 'unconfigured') {
        expect(
          find.text('Automatic synchronization is not configured.'),
          findsOneWidget,
        );
      }
      if (problem) {
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        expect(find.text('Festival account'), findsOneWidget);
        final retry = ['degraded', 'stale', 'temporary_failure', 'unavailable'].contains(status);
        expect(find.text('admin@example.test'), retry ? findsNothing : findsOneWidget);
        if (retry) {
          expect(find.textContaining('Do not replace the token or disable synchronization.'), findsOneWidget);
          expect(find.byType(Link), findsNothing);
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final scenario in [
    'ordered',
    'expired',
    'expired-full',
    'ordered-full',
    'fallback',
    'paid-deposit',
    'sent-deposit',
    'used-deposit',
    'paid-full',
    'sent-full',
    'storno',
    'waitlisted',
    'inactive',
    'cash',
    'healthy',
    'missing-account',
    'preparing_payment',
    'grace-period',
  ]) {
    testWidgets('bank warning visibility: $scenario', (tester) async {
      await EasyLocalization.ensureInitialized();
      final info = payment(
        paid: scenario.endsWith('full') ? 100 : 25,
        warning: scenario != 'cash' && scenario != 'healthy' && scenario != 'grace-period',
      );
      if (scenario == 'fallback') {
        info.bankSyncWarning = const BankSyncWarning(
          code: 'stale',
          bankAccountTitle: 'Festival account',
        );
      }
      if (scenario == 'missing-account') info.bankAccount = null;
      final order = OrderModel(
        state:
            scenario == 'inactive' ||
                scenario == 'cash' ||
                scenario == 'healthy' ||
                scenario == 'missing-account' ||
                scenario == 'fallback' || scenario == 'grace-period'
            ? 'ordered'
            : scenario.split('-').first,
        paymentInfoModel: info,
      );
      if (scenario == 'inactive') order.active = false;
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'unused',
          startLocale: const Locale('en'),
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
              home: Scaffold(body: OrderBankSyncWarning(order: order)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final visible =
          scenario == 'ordered' ||
          scenario == 'fallback' ||
          scenario == 'expired';
      expect(
        find.byIcon(Icons.warning_amber_rounded),
        visible ? findsOneWidget : findsNothing,
      );
      if (visible) {
        final reason = scenario == 'fallback'
            ? 'Bank payments have not been updated recently.'
            : 'Bank synchronization is off for the account receiving this payment.';
        final tooltip = tester
            .widget<IconButton>(find.byType(IconButton))
            .tooltip!;
        expect(tooltip, isNot(contains('Festival account')));
        if (scenario != 'fallback')
          expect(
            tooltip,
            contains('Contact a bank account administrator: Jane Admin'),
          );
        expect(tooltip, contains(reason));
        expect(tooltip, isNot(contains('Check the bank statement')));
        expect(
          tooltip,
          contains(
            scenario == 'fallback'
                ? 'Automatic retries continue.'
                : 'Jane Admin',
          ),
        );
        await tester.tap(find.byType(IconButton));
        await tester.pumpAndSettle();
        expect(find.text('Festival account'), findsOneWidget);
        expect(
          find.text(
            scenario == 'fallback'
                ? 'Automatic retries continue. Do not replace the token or disable synchronization. Contact Festapp support if the problem persists.'
                : 'admin@example.test',
          ),
          findsOneWidget,
        );
        expect(find.text(reason), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('account admin opens account settings from tooltip and dialog', (
    tester,
  ) async {
    final rights = RightsContextFixture.bankAccounts(manageableAccounts: {42});
    addTearDown(rights.dispose);
    final router = _WarningRouter(
      const Scaffold(
        body: BankSyncWarningButton(
          warning: BankSyncWarning(
            code: 'suspended',
            bankAccountTitle: 'My bank',
            bankAccountId: 42,
            isAdmin: true,
            contacts: [BankSyncContact(name: 'Jane Admin')],
          ),
        ),
      ),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'unused',
        startLocale: const Locale('en'),
        assetLoader: const _Translations(),
        child: Builder(
          builder: (context) => MaterialApp.router(
            routerConfig: router.config(),
            builder: DependencyMaterialBridge.builder,
            locale: context.locale,
            localizationsDelegates: [
              ...context.localizationDelegates,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: context.supportedLocales,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byIcon(Icons.warning_amber_rounded)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('Bank account settings'), findsOneWidget);
    expect(find.textContaining('Enable synchronization'), findsOneWidget);
    expect(find.textContaining('Jane Admin'), findsNothing);
    await mouse.moveTo(tester.getCenter(find.text('Bank account settings')));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('Bank account settings'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Bank account settings'));
    await tester.pumpAndSettle();
    expect(find.text('Connection 42'), findsOneWidget);
    expect(router.current.name, BankAccountConnectionSettingsRoute.name);
    router.pop();
    await tester.pumpAndSettle();
    await mouse.moveTo(const Offset(700, 500));
    await tester.tap(find.byIcon(Icons.warning_amber_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bank account settings'));
    await tester.pumpAndSettle();
    expect(find.text('Connection 42'), findsOneWidget);
    expect(find.byType(AppAlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  group('direct account connection destination', () {
    late RootSupabaseFixture fixture;
    var allowed = true;
    setUpAll(() async {
      fixture = await RootSupabaseFixture.open((request) {
        final path = request.url.path;
        if (path.endsWith('/get_my_admin_bank_accounts')) {
          return http.Response(
            jsonEncode(
              allowed
                  ? [
                      {
                        'id': 42,
                        'title': 'My bank',
                        'type': 'FIO',
                        'account_number': '123456/2010',
                        'bank_sync': {'state': 'suspended', 'mode': 'api'},
                      },
                    ]
                  : [],
            ),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        if (path.endsWith('/bank-sync-manage')) {
          return http.Response(
            jsonEncode({'state': 'suspended', 'mode': 'api'}),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        throw StateError('Unexpected bank settings request: $path');
      });
    });
    tearDownAll(() => fixture.dispose());
    for (final isAdmin in [true, false]) {
      testWidgets('opens only the requested administered account: $isAdmin', (
        tester,
      ) async {
        allowed = isAdmin;
        final rights = RightsContextFixture.bankAccounts(
          manageableAccounts: isAdmin ? {42} : {},
        );
        addTearDown(rights.dispose);
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en')],
            path: 'unused',
            startLocale: const Locale('en'),
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
                home: const BankAccountConnectionSettingsPage(accountId: '42'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(BankAccountSettingsScreen),
          isAdmin ? findsOneWidget : findsNothing,
        );
        if (isAdmin) {
          final screen = tester.widget<BankAccountSettingsScreen>(
            find.byType(BankAccountSettingsScreen),
          );
          expect(screen.connectionOnly, isTrue);
          expect(screen.account.id, 42);
          expect(screen.account.isAdmin, isTrue);
          expect(screen.unitId, isNull);
          expect(find.byType(Switch), findsOneWidget);
        } else {
          expect(
            find.text(
              'The account was not found or you do not have permission to manage it.',
            ),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  });
}
