import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';

void main() {
  testWidgets(
      'order email cells show empty text for missing email and preserve stored email',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      for (final email in [null, 'customer@example.org']) {
        final order = OrderModel(
          id: 6500,
          orderSymbol: '7G4K9M2R6A',
          state: OrderModel.orderedState,
          data: {'email': email},
          paymentInfoModel: PaymentInfoModel(),
        );
        expect(order.toTrinaRow(context).cells[EshopColumns.ORDER_EMAIL]!.value,
            email ?? '');
        expect(order.toTrinaRow(context).cells[EshopColumns.ORDER_ID]!.value,
            6500);
        expect(
            order.toTrinaRow(context).cells[EshopColumns.ORDER_SYMBOL]!.value,
            '7G4K9M2R6A');
        expect(order.toJson().containsKey('order_symbol'), isFalse);
        final history = OrderHistoryModel.fromOrderModel(order);
        expect(history.orderId, 6500);
        expect(
            history
                .toTrinaRow(context)
                .cells[EshopColumns.HISTORY_ORDER_SYMBOL]!
                .value,
            '7G4K9M2R6A');
        final ticket = TicketModel(id: 12)..relatedOrder = order;
        expect(
            ticket.toTrinaRow(context).cells[EshopColumns.ORDER_SYMBOL]!.value,
            '7G4K9M2R6A');
        final response = FormResponseModel.fromOrder(order, []);
        expect(response.toTrinaRow(context).cells[EshopColumns.ORDER_ID]!.value,
            6500);
        expect(
            response
                .toTrinaRow(context)
                .cells[EshopColumns.ORDER_SYMBOL]!
                .value,
            '7G4K9M2R6A');
        expect(OrderModel.fromJson({'id': 6500}).toBasicString(), '');
        expect(
            OrderModel.fromJson({'id': 6500, 'order_symbol': '7G4K9M2R6A'})
                .toBasicString(),
            '7G4K9M2R6A');
      }
      return const SizedBox.shrink();
    })));
  });
}
