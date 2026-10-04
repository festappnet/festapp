import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';

void main() {
  testWidgets('order email cells show empty text for missing email and preserve stored email',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      for (final email in [null, 'customer@example.org']) {
        final order = OrderModel(
          data: {'email': email},
          paymentInfoModel: PaymentInfoModel(),
        );
        expect(order.toTrinaRow(context).cells[EshopColumns.ORDER_EMAIL]!.value,
            email ?? '');
      }
      return const SizedBox.shrink();
    })));
  });
}
