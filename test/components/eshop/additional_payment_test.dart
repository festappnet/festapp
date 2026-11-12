import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/payment_operation_strings.dart';
import 'package:fstapp/components/payments/payment_policy_settings.dart';
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
  Completer<void>? transactionsGate;
  var transactionsFail = false, transactionsReads = 0, contextReads = 0;
  String? instructionsError;
  var legacyRefund = false;
  var policyFailure = false;
  var delayPolicy = false;
  final policyPending = <int, Completer<http.Response>>{};
  http.Response policyResponse(int unit) => http.Response(
    jsonEncode({
      'organizationId': 1,
      'unitId': unit,
      'revision': 1,
      'preferredMethod': 'stripe',
      'methods': {
        'stripe': {
          'id': 'stripe',
          'ready': false,
          'mode': 'inherit',
          'organizationEnabled': true,
          'policyEnabled': unit == 9,
          'inheritedFrom': 'organization',
          'configured': false,
          'canConfigure': unit == 9,
        },
      },
    }),
    200,
    request: http.Request(
      'POST',
      Uri.parse(
        'https://fixture.invalid/rest/v1/rpc/get_payment_method_policy',
      ),
    ),
    headers: {'content-type': 'application/json'},
  );
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
        if (endpoint == 'get_payment_method_policy') {
          final unit = payload['p_unit'] as int;
          if (delayPolicy)
            return (policyPending[unit] = Completer<http.Response>()).future;
          if (policyFailure)
            return http.Response(
              '{"message":"denied"}',
              403,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          return policyResponse(unit);
        }
        if (endpoint == 'get_transactions_for_order') {
          expect(payload['order_id'], 5);
          transactionsReads++;
          await transactionsGate?.future;
          if (transactionsFail)
            return http.Response(
              '{"message":"private fixture failure","code":"P0001"}',
              503,
              headers: {'content-type': 'application/json'},
            );
          return http.Response(
            jsonEncode({
              'order_state': 'sent',
              'transactions': legacyRefund
                  ? [
                      {
                        'id': 1,
                        'payment_info': 55,
                        'bank_account_id': 99,
                        'amount': 440,
                        'currency': 'CZK',
                        'counter_account': '19-2000145399',
                        'bank_code': '0800',
                        'counter_account_name': 'Jan Novák',
                        'ingest_source': 'legacy',
                        'transaction_type': 'Okamžitá příchozí platba',
                      },
                    ]
                  : [],
              'paymentOperations': {
                'invalidIdentity': false,
                'available': legacyRefund ? '440.00' : '0',
                'currency': 'CZK',
                'methods': [
                  if (legacyRefund)
                    {
                      'id': 'bank',
                      'displayName': 'Bank',
                      'instructions': true,
                      'verification': 'bank_event',
                    },
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
          contextReads++;
          return http.Response(
            jsonEncode({
              'code': 200,
              'context': {
                'invalidIdentity': false,
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
        if (endpoint == 'payment-operation' &&
            payload['input_data']['operation'] == 'bank_instructions') {
          return http.Response(
            jsonEncode({'error': instructionsError}),
            409,
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
    policyFailure = false;
    delayPolicy = false;
    policyPending.clear();
    paymentOutcome = 'success';
    transactionsGate = null;
    transactionsFail = false;
    transactionsReads = 0;
    contextReads = 0;
    instructionsError = null;
    legacyRefund = false;
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
                  key: ObjectKey(order),
                  columns: EshopColumns.generateColumns(
                    context,
                    [
                      EshopColumnIds.PAYMENT_INFO_PAID,
                      EshopColumnIds.PAYMENT_INFO_RETURNED,
                    ],
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
    final plusRect = tester.getRect(find.byIcon(Icons.add_circle_outline));
    final minusRect = tester.getRect(find.byIcon(Icons.remove_circle_outline));
    expect(
      plusRect.right,
      lessThan(minusRect.left),
      reason: 'Payment and refund actions belong to separate grid columns',
    );
    final grid = tester.widget<TrinaGrid>(find.byType(TrinaGrid));
    expect(
      minusRect.left - plusRect.left,
      greaterThanOrEqualTo(grid.columns.first.width - 1),
    );
  }

  Future<void> policy(WidgetTester tester, int unit) async {
    await _environment.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: PaymentPolicySettings(
            key: const ValueKey('policy'),
            organizationId: 1,
            unitId: unit,
            onConfigure: (_) {},
            configureMethods: const {'stripe'},
          ),
        ),
      ),
    );
  }

  testWidgetsWithEnvironment(
    () => _environment,
    'payment policy retry recovers denied load and exposes supported onboarding',
    (tester) async {
      policyFailure = true;
      await policy(tester, 9);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byIcon(Icons.star), findsNothing);
      policyFailure = false;
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byType(TextButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgetsWithEnvironment(
    () => _environment,
    'payment policy discards late responses after unit switch',
    (tester) async {
      delayPolicy = true;
      final selected = ValueNotifier<int>(9);
      addTearDown(selected.dispose);
      await _environment.pumpWidget(
        tester,
        MaterialApp(
          builder: DependencyMaterialBridge.builder,
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: selected,
              builder: (_, unit, __) => PaymentPolicySettings(
                key: const ValueKey('policy'),
                organizationId: 1,
                unitId: unit,
                onConfigure: (_) {},
                configureMethods: const {'stripe'},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      selected.value = 10;
      await tester.pump();
      await tester.pump();
      policyPending[10]!.complete(policyResponse(10));
      await tester.pumpAndSettle();
      expect(find.byType(TextButton), findsNothing);
      policyPending[9]!.complete(policyResponse(9));
      await tester.pumpAndSettle();
      expect(
        find.byType(TextButton),
        findsNothing,
        reason: 'unit A cannot restore its onboarding in unit B',
      );
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

  Future<void> tapWithIo(WidgetTester tester, Finder target) async {
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();
  }

  test(
    'bank instructions preserve the structured server error through transport',
    () async {
      instructionsError = 'SPD_DOMESTIC_ACCOUNT_REQUIRED';
      await expectLater(
        DbOrders.bankRefundInstructions({
          'orderId': 5,
          'currency': 'CZK',
          'amount': '1000',
          'recipientName': 'Jan Novák',
          'recipientIban': 'SK1211100000001571891008',
        }),
        throwsA(
          isA<PaymentInstructionsException>().having(
            (error) => error.code,
            'code',
            'SPD_DOMESTIC_ACCOUNT_REQUIRED',
          ),
        ),
      );
      expect(payments, isEmpty);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'payment dialog opens before its data arrives and uses one authorized read',
    (tester) async {
      final gate = transactionsGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await grid(tester, paidOrder('sent', actions: {'view', 'edit', 'send'}));
      await tapWithIo(tester, plus());
      expect(find.byType(AppAlertDialog), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      gate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentOperationDialog), findsOneWidget);
      expect(find.byKey(const ValueKey('paymentAmount')), findsOneWidget);
      expect(transactionsReads, 1);
      expect(contextReads, 0);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'refund loading preserves legacy incoming bank recipient details',
    (tester) async {
      // Open the on-disk intent store on the real clock before the HTTP replay.
      await tester.runAsync(() => DbOrders.pendingPaymentOperation(5));
      legacyRefund = true;
      final gate = transactionsGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final order = paidOrder('sent', actions: {'view', 'edit', 'send'});
      order.paymentInfoModel!.paymentOperations = const PaymentOperationContext(
        available: '440.00',
        methods: [
          PaymentOperationMethod(
            id: 'bank',
            displayName: 'Bank',
            instructions: true,
            verification: 'bank_event',
          ),
        ],
      );
      await grid(tester, order);
      await tapWithIo(
        tester,
        find.widgetWithIcon(IconButton, Icons.remove_circle_outline),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentOperationDialog), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('paymentAmount')))
            .controller!
            .text,
        '440.00',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(
                TextFormField,
                PaymentOperationStrings.text('recipientName'),
              ),
            )
            .controller!
            .text,
        'Jan Novák',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(
                TextFormField,
                PaymentOperationStrings.text('recipientIban'),
              ),
            )
            .controller!
            .text,
        'CZ6508000000192000145399',
      );
      expect(
        find.text(PaymentOperationStrings.text('incomingAccountHint')),
        findsOneWidget,
      );
      expect(transactionsReads, 1);
      expect(contextReads, 0);
      expect(payments, isEmpty);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'loading payment dialog can close before the request completes',
    (tester) async {
      final gate = transactionsGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      await grid(tester, paidOrder('sent', actions: {'view', 'edit', 'send'}));
      await tapWithIo(tester, plus());
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      gate.complete();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppAlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'failed payment loading offers retry inside the open dialog',
    (tester) async {
      transactionsFail = true;
      await grid(tester, paidOrder('sent', actions: {'view', 'edit', 'send'}));
      await tapWithIo(tester, plus());
      await tester.pumpAndSettle();
      expect(
        find.text(PaymentOperationStrings.text('loadFailed')),
        findsOneWidget,
      );
      expect(find.text('private fixture failure'), findsNothing);
      transactionsFail = false;
      await tapWithIo(tester, find.text(CommonStrings.retry));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentOperationDialog), findsOneWidget);
      expect(transactionsReads, 2);
      expect(contextReads, 0);
    },
  );

  testWidgetsWithEnvironment(
    () => _environment,
    'payment action buttons combine capabilities with available refund balance',
    (tester) async {
      const methods = [
        PaymentOperationMethod(
          id: 'cash',
          displayName: 'Cash',
          record: true,
          refund: true,
        ),
        PaymentOperationMethod(
          id: 'bank',
          displayName: 'Bank',
          instructions: true,
          verification: 'bank_event',
        ),
      ];
      for (final available in ['0', '0.00', '-1', 'invalid', '0.01', '500']) {
        final order = paidOrder('sent', actions: {'view', 'edit', 'send'});
        order.paymentInfoModel!.paymentOperations = PaymentOperationContext(
          available: available,
          methods: methods,
        );
        await grid(tester, order);
        expect(tester.widget<IconButton>(plus()).onPressed, isNotNull);
        final minus = find.widgetWithIcon(
          IconButton,
          Icons.remove_circle_outline,
        );
        final positive = (double.tryParse(available) ?? 0) > 0;
        expect(
          tester.widget<IconButton>(minus).onPressed,
          positive ? isNotNull : isNull,
          reason:
              'Refund availability must match the server balance: $available',
        );
        if (!positive) {
          await tester.tap(minus);
          await tester.pumpAndSettle();
          expect(find.byType(PaymentOperationDialog), findsNothing);
        }
      }
      expect(payments, isEmpty);
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
