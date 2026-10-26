import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'dart:convert';
import 'dart:io';
import 'package:festapp_core/eshop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/views/products_dialog.dart';
import 'package:fstapp/components/eshop/views/product_info_panel.dart';
import 'package:fstapp/components/stripe_payments/card_refund_decision_api.dart';
import 'package:fstapp/components/stripe_payments/card_refund_decision_panel.dart';
import '../../support/fixtures/widget_environment_fixture.dart';

class ReadOnlyRefundApi implements CardRefundDecisionApi {
  @override
  Future<CardRefundDetail?> read(int orderId) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  WidgetEnvironmentFixture.register();
  late Map<String, dynamic> catalog;
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    catalog =
        jsonDecode(File('assets/translations/cs.json').readAsStringSync());
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'), translations: catalog);
  });
  for (final stripe in [true, false]) {
    for (final canManage in [true, false]) {
      testWidgets(
          'Stripe=$stripe editRights=$canManage separates product changes from admission/email',
          (tester) async {
        tester.view.physicalSize = const Size(1400, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final order = OrderModel(
            id: 1,
            state: 'paid',
            paymentMethod: stripe ? 'stripe' : 'bank',
            allowedActions: canManage ? {'view', 'edit'} : {'view'},
            price: 98.76,
            currencyCode: 'CZK');
        final bundle = TicketDetailsBundle(
          order: order,
          ticket: TicketModel(
              id: 2,
              state: 'paid',
              relatedOrder: order,
              relatedProducts: [
                ProductModel(
                    id: 3,
                    title: 'Admission',
                    price: 98.76,
                    currencyCode: 'CZK')
              ]),
          orderHistory: OrderHistoryInfo(isNewerVersionAvailable: false),
          changes: OrderChangeSummary.fromJson({
            'version': 1,
            'cancelledTickets': [],
            'removedTickets': [],
            'addedTickets': [],
            'productChanges': [],
            'referenceTotal': 98.76,
            'currentTotal': 98.76,
            'currencyCode': 'CZK',
            'hasChanges': false
          }),
        );
        await environment.pumpWidget(
            tester,
            MaterialApp(builder: DependencyMaterialBridge.builder,
                home: Scaffold(
                    body: ProductsDialog(
              ticketId: 2,
              loadTicket: (_) async => bundle,
              refundApi: ReadOnlyRefundApi(),
            ))));
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.edit_outlined),
            stripe ? findsNothing : findsOneWidget);
        expect(find.byIcon(Icons.delete_outline),
            stripe ? findsNothing : findsOneWidget);
        expect(find.byIcon(Icons.add_shopping_cart),
            stripe ? findsNothing : findsOneWidget);
        expect(find.text(catalog['CardPayments']['productsImmutable']),
            stripe ? findsOneWidget : findsNothing);
        expect(
            tester
                .widget<ProductInfoPanel>(find.byType(ProductInfoPanel))
                .onSendUpdate,
            canManage ? isNotNull : isNull);
        expect(
            tester
                .widget<CardRefundDecisionPanel>(
                    find.byType(CardRefundDecisionPanel))
                .allowEdit,
            canManage);
        if (!stripe) {
          expect(
              tester
                  .widget<IconButton>(
                      find.widgetWithIcon(IconButton, Icons.edit_outlined))
                  .onPressed,
              canManage ? isNotNull : isNull);
        }
      });
    }
  }
}
