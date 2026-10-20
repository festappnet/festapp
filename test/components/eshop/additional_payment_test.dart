import '../../support/fixtures/widget_environment_fixture.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/views/add_cash_payment_dialog.dart';
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
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(
          autoRefreshToken: false, localStorage: EmptyLocalStorage()),
      httpClient: MockClient((request) async {
        final endpoint = request.url.path.split('/').last;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        if (endpoint == 'get_transactions_for_order') {
          expect(payload['order_id'], 5);
          return http.Response(
              jsonEncode({
                'order_state': 'sent',
                'transactions': [],
                'payment_info': {
                  'id': 55,
                  'bank_account': 99,
                  'amount': 1900,
                  'paid': 1900,
                  'currency_code': 'CZK'
                },
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json'});
        }
        if (endpoint == 'insert_manual_transaction') {
          payments.add(payload);
          return http.Response('null', 200,
              request: request, headers: {'content-type': 'application/json'});
        }
        throw StateError('Unexpected fixture request: ${request.url.path}');
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    payments.clear();
    _environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync())
                as Map<String, dynamic>);
    final previous = RightsService.occasionLinkModelNotifier.value;
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasionUser: OccasionUserModel.fromJson({'is_editor_order': true}),
    );
    addTearDown(() => RightsService.occasionLinkModelNotifier.value = previous);
  });

  Future<void> grid(WidgetTester tester, OrderModel order,
      {Future<void> Function()? refresh}) async {
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
                    locale: localized.locale,
                    supportedLocales: localized.supportedLocales,
                    localizationsDelegates: localized.localizationDelegates,
                    home: Scaffold(
                        body: Builder(
                            builder: (context) => TrinaGrid(
                                  columns:
                                      EshopColumns.generateColumns(context, [
                                    EshopColumnIds.PAYMENT_INFO_PAID
                                  ], data: {
                                    'unitId': 9,
                                    EshopColumnIds.PAYMENT_INFO_PAID: refresh,
                                  }),
                                  rows: [order.toTrinaRow(context)],
                                )))))));
    await tester.pumpAndSettle();
  }

  Finder plus() => find
      .ancestor(
          of: find.byIcon(Icons.add_circle_outline),
          matching: find.byType(InkWell))
      .first;
  OrderModel paidOrder(String state, {Set<String>? actions}) {
    final order = OrderModel(
        id: 5,
        state: state,
        price: 1900,
        paymentInfo: 55,
        currencyCode: 'CZK',
        allowedActions: actions);
    order.paymentInfoModel =
        PaymentInfoModel(id: 55, amount: 1900, paid: 1900, currencyCode: 'CZK');
    return order;
  }

  testWidgetsWithEnvironment(() => _environment,
      'fully paid sent order opens actual cash dialog and submits an additional payment',
      (tester) async {
    final order = paidOrder('sent', actions: {'view', 'edit', 'send'});
    var refreshed = 0;
    await grid(tester, order, refresh: () async {
      refreshed++;
    });
    expect(tester.widget<InkWell>(plus()).onTap, isNotNull);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(find.byType(AddCashPaymentDialog), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, '500');
    await tester
        .tap(find.widgetWithText(ElevatedButton, OrdersStrings.addPayment));
    await tester.pumpAndSettle();
    expect(payments, hasLength(1));
    expect(payments.single['p_amount'], 500);
    expect(payments.single['p_payment_info_id'], 55);
    expect(payments.single['p_unit_id'], 9);
    expect(payments.single['p_currency'], 'CZK');
    expect(refreshed, 1);
    expect(order.state, 'sent');
    expect(order.allows('paid'), isFalse,
        reason: 'Adding cash is separate from marking an order paid');
    expect(find.byType(AddCashPaymentDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final state in ['waitlisted', 'preparing_payment', 'storno']) {
    testWidgetsWithEnvironment(() => _environment,
        '$state remains protected even with editor role and edit metadata',
        (tester) async {
      await grid(tester, paidOrder(state, actions: {'view', 'edit', 'paid'}));
      expect(tester.widget<InkWell>(plus()).onTap, isNull);
      expect(payments, isEmpty);
    });
  }
  testWidgetsWithEnvironment(
      () => _environment, 'read-only viewer cannot add payment to sent order',
      (tester) async {
    RightsService.occasionLinkModelNotifier.value = OccasionLinkModel(
      occasionUser: OccasionUserModel.fromJson({'is_editor_order_view': true}),
    );
    await grid(tester, paidOrder('sent', actions: {'view', 'edit', 'send'}));
    expect(tester.widget<InkWell>(plus()).onTap, isNull);
    expect(payments, isEmpty);
  });
  testWidgetsWithEnvironment(() => _environment,
      'missing edit capability remains protected for an editor',
      (tester) async {
    await grid(tester, paidOrder('sent', actions: {'view', 'send'}));
    expect(tester.widget<InkWell>(plus()).onTap, isNull);
  });
}
