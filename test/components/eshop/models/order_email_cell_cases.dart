import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets(
      'order email cells show empty text for missing email and preserve stored email',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      for (final email in [null, 'customer@example.org']) {
        final order = OrderModel(
          id: 6500,
          orderSymbol: '7G4K9M2R6A',
          state: OrderModel.orderedState,
          data: {'email': email},
          paymentInfoModel: PaymentInfoModel(),
        );
        expect(
            order.toTrinaRow(context).cells[EshopColumnIds.ORDER_EMAIL]!.value,
            email ?? '');
        expect(order.toTrinaRow(context).cells[EshopColumnIds.ORDER_ID]!.value,
            6500);
        expect(
            order.toTrinaRow(context).cells[EshopColumnIds.ORDER_SYMBOL]!.value,
            '7G4K9M2R6A');
        expect(order.toJson().containsKey('order_symbol'), isFalse);
        final restored =
            OrderModel.fromPlutoJson(order.toTrinaRow(context).toJson());
        expect(restored.id, 6500);
        expect(restored.toBasicString(),
            ['7G4K9M2R6A', if (email != null) email].join(' - '));
        final history = OrderHistoryModel.fromOrderModel(order);
        expect(history.orderId, 6500);
        expect(
            history
                .toTrinaRow(context)
                .cells[EshopColumnIds.HISTORY_ORDER_SYMBOL]!
                .value,
            '7G4K9M2R6A');
        final ticket = TicketModel(id: 12)..relatedOrder = order;
        expect(
            ticket
                .toTrinaRow(context)
                .cells[EshopColumnIds.ORDER_SYMBOL]!
                .value,
            '7G4K9M2R6A');
        final response = FormResponseModel.fromOrder(order, []);
        expect(
            response.toTrinaRow(context).cells[EshopColumnIds.ORDER_ID]!.value,
            6500);
        expect(
            response
                .toTrinaRow(context)
                .cells[EshopColumnIds.ORDER_SYMBOL]!
                .value,
            '7G4K9M2R6A');
        expect(OrderModel.fromJson({'id': 6500}).toBasicString(), '#6500');
        expect(
            OrderModel.fromJson({'id': 6500, 'order_symbol': '7G4K9M2R6A'})
                .toBasicString(),
            '7G4K9M2R6A');
      }
      return const SizedBox.shrink();
    })));
  });

  test('deletion identifies customer and keeps the edited note', () {
    final order = OrderModel.fromPlutoJson({
      EshopColumnIds.ORDER_ID: 6500,
      EshopColumnIds.ORDER_SYMBOL: '7G4K9M2R6A',
      EshopColumnIds.ORDER_DATA: 'Jana Nováková',
      EshopColumnIds.ORDER_EMAIL: 'jana@example.org',
      EshopColumnIds.ORDER_NOTE_HIDDEN: 'Edited note',
    });
    expect(
        order.toBasicString(), '7G4K9M2R6A - Jana Nováková - jana@example.org');
    expect(order.noteHidden, 'Edited note');
    expect(OrderModel(id: 6500).toBasicString(), '#6500');
  });
}
