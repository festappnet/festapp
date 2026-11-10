import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/models/payment_operation_context.dart';
import 'package:fstapp/services/storage_helper.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'dart:async';

import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/data_services/authorization_capabilities.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

import 'package:fstapp/components/eshop/eshop_column_ids.dart';

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/payment_operation_dialog.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
// Supabase's PKCE fixture uses its shared_preferences dependency.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:trina_grid/trina_grid.dart';

late WidgetEnvironmentFixture _environment;

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  WidgetEnvironmentFixture.register();
  TestWidgetsFlutterBinding.ensureInitialized();
  final payments = <Map<String, dynamic>>[];
  late Directory storage;
  final previousPaths = PathProviderPlatform.instance;
  late Completer<void> recorded;
  var paymentOutcome = 'success';
  setUpAll(() async {
    storage = await Directory.systemTemp.createTemp('festapp-cash-widget-');
    PathProviderPlatform.instance = _CashDocuments(storage.path);
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        detectSessionInUri: false,
        localStorage: EmptyLocalStorage(),
      ),
      httpClient: MockClient((request) async {
        final endpoint = request.url.path.split('/').last;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        if (endpoint == 'get_transactions_for_order') {
          expect(payload['order_id'], 5);
          return http.Response(
            jsonEncode({
              'order_state': 'sent',
              'transactions': [],
              'paymentOperations': {
                'methods': [
                  {
                    'id': 'cash',
                    'displayName': 'Hotově',
                    'record': true,
                    'verification': 'local_commit',
                  },
                ],
              },
              'actions': {
                'canAddCash': true,
                'canConfigureBank': true,
                'unitId': 9,
                'bankState': 'configured',
              },
              'payment_info': {
                'id': 55,
                'bank_account': 99,
                'amount': 1900,
                'paid': 1900,
                'currency_code': 'CZK',
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        if (endpoint == 'payment-operation' &&
            payload['input_data']['operation'] == 'read') {
          return http.Response(
            jsonEncode({
              'code': 200,
              'context': {
                'methods': [
                  {
                    'id': 'cash',
                    'displayName': 'Hotově',
                    'record': true,
                    'verification': 'local_commit',
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (endpoint == 'payment-operation') {
          payments.add(payload);
          if (paymentOutcome != 'success')
            return http.Response(
              jsonEncode({
                'error': 'PAYMENT_TEST_REJECTED',
                if (paymentOutcome == 'rejected') 'mutationNotApplied': true,
              }),
              paymentOutcome == 'rejected' ? 409 : 503,
              headers: {'content-type': 'application/json'},
            );
          if (!recorded.isCompleted) recorded.complete();
          return http.Response(
            '{"code":200,"nextAction":"recorded"}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        throw StateError('Unexpected fixture request: ${request.url.path}');
      }),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
    await StorageHelper.closeDatabase('default.db');
    PathProviderPlatform.instance = previousPaths;
    await storage.delete(recursive: true);
  });
  setUp(() {
    payments.clear();
    paymentOutcome = 'success';
    recorded = Completer<void>();
    _environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations: jsonDecode(
        File('assets/translations/cs.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      capabilities: {AuthorizationCapabilities.ordersWrite: true},
      occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}),
    );
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  Future<void> grid(
    WidgetTester tester,
    OrderModel order, {
    Future<void> Function()? refresh,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _environment.pumpWidget(
      tester,
      EasyLocalization(
        supportedLocales: const [Locale('cs')],
        path: 'unused',
        assetLoader: _Translations(),
        child: Builder(
          builder: (localized) => MaterialApp(
            builder: DependencyMaterialBridge.builder,
            locale: localized.locale,
            supportedLocales: localized.supportedLocales,
            localizationsDelegates: [
              ...localized.localizationDelegates,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(
              body: Builder(
                builder: (context) => TrinaGrid(
                  columns: EshopColumns.generateColumns(
                    context,
                    [EshopColumnIds.PAYMENT_INFO_PAID],
                    data: {
                      'unitId': 9,
                      EshopColumnIds.PAYMENT_INFO_PAID: refresh,
                    },
                  ),
                  rows: [order.toTrinaRow(context)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder plus() => find.widgetWithIcon(IconButton, Icons.add_circle_outline);
  OrderModel paidOrder(String state, {Set<String>? actions}) {
    final order = OrderModel(
      id: 5,
      state: state,
      price: 1900,
      paymentInfo: 55,
      currencyCode: 'CZK',
      allowedActions: actions,
    );
    order.paymentInfoModel = PaymentInfoModel(
      id: 55,
      amount: 1900,
      paid: 1900,
      currencyCode: 'CZK',
      paymentOperations:
          state == 'sent' &&
              (actions?.contains('edit') ?? false) &&
              RightsService.canUpdateOrders()
          ? const PaymentOperationContext(
              methods: [
                PaymentOperationMethod(
                  id: 'cash',
                  displayName: 'Hotově',
                  record: true,
                  verification: 'local_commit',
                ),
              ],
            )
          : const PaymentOperationContext(),
    );
    return order;
  }

  test('uncertain payment survives storage reopen and fences another amount or date', () async {
    final original = {
      'operation': 'prepare_refund',
      'orderId': 345,
      'method': 'cash',
      'currency': 'EUR',
      'amount': '30.50',
      'receivedAt': '2026-11-10T09:01:00Z',
      'note': 'Original cash receipt',
    };
    paymentOutcome = 'uncertain';
    await expectLater(
      DbOrders.commandPaymentOperation(original),
      throwsA(isA<FunctionException>()),
    );
    final firstId = payments.single['p_command_id'];
    await StorageHelper.closeDatabase('default.db');
    final recovered = await DbOrders.pendingPaymentOperation(345);
    expect(recovered, original);
    await expectLater(
      DbOrders.commandPaymentOperation({
        ...original,
        'receivedAt': '2026-11-11T09:01:00Z',
        'amount': '31.00',
      }),
      throwsStateError,
    );
    expect(payments, hasLength(1));
    // A failed reauthorization/replay cannot erase an earlier unknown outcome.
    paymentOutcome = 'rejected';
    await expectLater(
      DbOrders.commandPaymentOperation(recovered!),
      throwsA(isA<FunctionException>()),
    );
    expect(await DbOrders.pendingPaymentOperation(345), original);
    paymentOutcome = 'success';
    await DbOrders.commandPaymentOperation(recovered);
    expect(payments.last['p_command_id'], firstId);
    expect(payments.last['input_data'], original);
    expect(await DbOrders.pendingPaymentOperation(345), isNull);
  });
  test('new private draft nonce allows equal money and date after completed payment', () async {
    const namespace = 'orders.payment.operation', actor = 'test-new-draft';
    final money = {
      'operation': 'record_payment',
      'orderId': 348,
      'amount': '20.50',
      'method': 'cash',
      'currency': 'EUR',
      'receivedAt': '2026-11-10T00:00:00Z',
      'note': 'At entrance',
    };
    final original = {
      ...money,
      'clientIntentId': ClientCommandIdentity.newCommandId(),
    };
    final first = await ClientCommandIdentity.claimIntent(
      namespace,
      original,
      principalBinding: actor,
      scopeBinding: 'order:348',
      requestJson: jsonEncode(original),
    );
    await ClientCommandIdentity.registerDispatch(
      namespace,
      original,
      commandId: first,
      principalBinding: actor,
    );
    await ClientCommandIdentity.completeIntent(
      namespace,
      original,
      commandId: first,
      principalBinding: actor,
      retainIdentity: true,
    );
    final newDraft = {
      ...money,
      'clientIntentId': ClientCommandIdentity.newCommandId(),
    };
    final second = await ClientCommandIdentity.claimIntent(
      namespace,
      newDraft,
      principalBinding: actor,
      scopeBinding: 'order:348',
      requestJson: jsonEncode(newDraft),
    );
    expect(
      second,
      isNot(first),
      reason: 'intentional equal payments are separate drafts',
    );
    await ClientCommandIdentity.completeIntent(
      namespace,
      newDraft,
      commandId: second,
      principalBinding: actor,
    );
  });
  test('two tab dispatch claims retain rollback fence and completed payload identity', () async {
    const namespace = 'orders.payment.operation', actor = 'test-two-tabs';
    final payload = {
      'operation': 'record_payment',
      'orderId': 347,
      'amount': '20.50',
      'method': 'cash',
      'currency': 'EUR',
      'receivedAt': '2026-11-10T10:01:00Z',
    };
    final first = await ClientCommandIdentity.claimIntent(
      namespace,
      payload,
      principalBinding: actor,
      scopeBinding: 'order:347',
      requestJson: jsonEncode(payload),
    );
    final second = await ClientCommandIdentity.claimIntent(
      namespace,
      payload,
      principalBinding: actor,
      scopeBinding: 'order:347',
      requestJson: jsonEncode(payload),
    );
    expect(second, first);
    expect(
      await ClientCommandIdentity.registerDispatch(
        namespace,
        payload,
        commandId: first,
        principalBinding: actor,
      ),
      1,
    );
    expect(
      await ClientCommandIdentity.registerDispatch(
        namespace,
        payload,
        commandId: second,
        principalBinding: actor,
      ),
      2,
    );
    expect(
      await ClientCommandIdentity.completeIntent(
        namespace,
        payload,
        commandId: first,
        principalBinding: actor,
        onlyIfSingleDispatch: true,
      ),
      isFalse,
    );
    expect(
      await ClientCommandIdentity.pendingIntent(
        namespace,
        principalBinding: actor,
        scopeBinding: 'order:347',
      ),
      isNotNull,
    );
    await ClientCommandIdentity.completeIntent(
      namespace,
      payload,
      commandId: first,
      principalBinding: actor,
      retainIdentity: true,
    );
    final replay = await ClientCommandIdentity.claimIntent(
      namespace,
      payload,
      principalBinding: actor,
      scopeBinding: 'order:347',
      requestJson: jsonEncode(payload),
    );
    expect(
      replay,
      first,
      reason: 'a late uncertain tab must reuse the completed command',
    );
    await ClientCommandIdentity.completeIntent(
      namespace,
      payload,
      commandId: replay,
      principalBinding: actor,
    );
    await expectLater(
      ClientCommandIdentity.registerDispatch(
        namespace,
        payload,
        commandId: first,
        principalBinding: actor,
      ),
      throwsStateError,
    );
  });
  test(
    'only proven transaction rollback releases intent for corrected draft',
    () async {
      final original = {
        'operation': 'record_payment',
        'orderId': 346,
        'method': 'cash',
        'currency': 'EUR',
        'amount': '30.50',
        'receivedAt': '2026-11-10T09:01:00Z',
      };
      paymentOutcome = 'rejected';
      await expectLater(
        DbOrders.commandPaymentOperation(original),
        throwsA(isA<PaymentOperationRejected>()),
      );
      final firstId = payments.single['p_command_id'];
      expect(await DbOrders.pendingPaymentOperation(346), isNull);
      paymentOutcome = 'success';
      await DbOrders.commandPaymentOperation({...original, 'amount': '30.00'});
      expect(payments.last['p_command_id'], isNot(firstId));
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'fully paid sent order opens actual cash dialog and submits an additional payment',
    (tester) async {
      final order = paidOrder('sent', actions: {'view', 'edit', 'send'});
      var refreshed = 0;
      await grid(
        tester,
        order,
        refresh: () async {
          refreshed++;
        },
      );
      expect(tester.widget<IconButton>(plus()).onPressed, isNotNull);
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.add_circle_outline));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.byType(PaymentOperationDialog), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '500');
      await tester.runAsync(() async {
        await tester.tap(
          find.widgetWithText(ElevatedButton, OrdersStrings.addPayment),
        );
        await recorded.future.timeout(const Duration(seconds: 10));
        // Let PostgREST finish its real async response before returning to the fake clock.
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(payments, hasLength(1));
      expect(payments.single['input_data']['amount'], '500');
      expect(payments.single['input_data']['orderId'], 5);
      expect(payments.single['input_data']['operation'], 'record_payment');
      expect(payments.single['input_data']['currency'], 'CZK');
      expect(refreshed, 1);
      expect(order.state, 'sent');
      expect(
        order.allows('paid'),
        isFalse,
        reason: 'Adding cash is separate from marking an order paid',
      );
      expect(find.byType(PaymentOperationDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in ['waitlisted', 'preparing_payment', 'storno']) {
    testWidgetsWithEnvironment(
      () => _environment,
      '$state remains protected even with editor role and edit metadata',
      (tester) async {
        await grid(tester, paidOrder(state, actions: {'view', 'edit', 'paid'}));
        expect(tester.widget<IconButton>(plus()).onPressed, isNull);
        expect(payments, isEmpty);
      },
    );
  }
  testWidgetsWithEnvironment(
    () => _environment,
    'read-only viewer cannot add payment to sent order',
    (tester) async {
      RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
        occasionUser: OccasionUserModel.fromJson({
          'is_editor_order_view': true,
        }),
      );
      await grid(tester, paidOrder('sent', actions: {'view', 'edit', 'send'}));
      expect(tester.widget<IconButton>(plus()).onPressed, isNull);
      expect(payments, isEmpty);
    },
  );
  testWidgetsWithEnvironment(
    () => _environment,
    'missing edit capability remains protected for an editor',
    (tester) async {
      await grid(tester, paidOrder('sent', actions: {'view', 'send'}));
      expect(tester.widget<IconButton>(plus()).onPressed, isNull);
    },
  );
}

class _CashDocuments extends PathProviderPlatform {
  _CashDocuments(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
