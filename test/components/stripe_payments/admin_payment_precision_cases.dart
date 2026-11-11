import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/views/product_info_panel.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() => environment = WidgetEnvironmentFixture(
      locale: const Locale('cs'),
      translations:
          jsonDecode(File('assets/translations/cs.json').readAsStringSync())));

  for (final method in [null, 'bank', 'stripe']) {
    testWidgetsWithEnvironment(() => environment,
        '$method admin order, payment, refund, ticket and detail formatting',
        (tester) async {
      final payment = PaymentInfoModel.fromJson({
        'payment_method': method,
        'amount': '123.45',
        'paid': '123.45',
        'returned': '12.67',
        'currency_code': 'CZK',
      });
      final order = OrderModel(
          id: 10,
          state: 'paid',
          price: 123.45,
          currencyCode: 'CZK',
          paymentInfoModel: payment);
      final ticket = TicketModel(id: 20, relatedOrder: order)
        ..totalPrice = 123.45;
      late BuildContext localized;
      await environment.pumpWidget(tester, MaterialApp(builder: DependencyMaterialBridge.builder, home: Scaffold(
        body: Builder(builder: (context) {
          localized = context;
          return ProductInfoPanel(
            order: order,
            paymentInfo: payment,
            ticket: ticket,
            orderHistory: OrderHistoryInfo(isNewerVersionAvailable: false),
          );
        }),
      )));
      await tester.pumpAndSettle();
      final row = order.toTrinaRow(localized);
      final expectedPrice = method == 'stripe' ? '123,45' : '123';
      final expectedRefund = method == 'stripe' ? '12,67' : '13';
      for (final field in [
        EshopColumnIds.ORDER_PRICE,
        EshopColumnIds.PAYMENT_INFO_AMOUNT,
        EshopColumnIds.PAYMENT_INFO_PAID
      ]) {
        expect(row.cells[field]!.value, contains(expectedPrice));
        expect(row.cells[field]!.value, contains('Kč'));
        if (method != 'stripe')
          expect(row.cells[field]!.value, isNot(contains(',')));
      }
      expect(row.cells[EshopColumnIds.PAYMENT_INFO_RETURNED]!.value,
          contains(expectedRefund));
      expect(
          ticket
              .toTrinaRow(localized)
              .cells[EshopColumnIds.TICKET_TOTAL_PRICE]!
              .value,
          contains(expectedPrice));
      final paymentDetail = tester.widget<SelectableText>(
          find.byWidgetPredicate((widget) =>
              widget is SelectableText &&
              (widget.data?.contains(' / ') ?? false)));
      final amounts = paymentDetail.data!.split(' / ');
      expect(amounts, hasLength(2));
      for (final amount in amounts) {
        expect(amount, contains(expectedPrice));
        if (method != 'stripe') expect(amount, isNot(contains(',')));
      }
    });
  }

  testWidgetsWithEnvironment(() => environment,
      'history projection preserves Stripe cents without a stitched payment record',
      (tester) async {
    final order = OrderModel.fromJson(
        {'id': 10, 'payment_method': 'stripe', 'state': 'paid'});
    final history =
        OrderHistoryModel(price: 123.45, currencyCode: 'EUR', state: 'paid')
          ..orderModel = order;
    late BuildContext localized;
    await environment.pumpWidget(tester,
        MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      localized = context;
      return const SizedBox.shrink();
    })));
    await tester.pumpAndSettle();
    final price = history
        .toTrinaRow(localized)
        .cells[EshopColumnIds.HISTORY_PRICE]!
        .value;
    expect(price, contains('123,45'));
    expect(price, contains('€'));
    expect(order.paymentInfoModel, isNull);
  });
}
