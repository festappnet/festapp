import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/components/eshop/views/order_delete_dialog.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  testWidgets('ticket row preserves labels, parent and edited note',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      final order = OrderModel(
        id: 10,
        orderSymbol: 'ORDER10',
        data: {
          'name': 'Jana',
          'surname': 'Nováková',
          'email': 'jana@example.org'
        },
      );
      final ticket = TicketModel(
        id: 20,
        ticketSymbol: 'TICKET20',
        relatedOrder: order,
        relatedSpot: BlueprintObjectModel(title: 'Stůl 3, místo 2'),
        relatedProducts: [ProductModel(title: 'Vstupné')],
        noteHidden: 'Original note',
      );
      final row = ticket.toTrinaRow(context);
      row.cells[EshopColumnIds.TICKET_NOTE_HIDDEN]!.value = 'Edited note';
      final restored = TicketModel.fromPlutoJson(row.toJson());
      expect(restored.toBasicString(), 'TICKET20 - Stůl 3, místo 2 - Vstupné');
      expect(restored.relatedOrder, same(order));
      expect(restored.noteHidden, 'Edited note');
      expect(restored.id, 20);
      expect(TicketModel(id: 21).toBasicString(), '#21');
      expect(TicketModel().toBasicString(), '');
      return const SizedBox();
    })));
  });

  testWidgets('groups by order identity and lists only selected tickets',
      (tester) async {
    final order = OrderModel(
      id: 10,
      orderSymbol: 'ORDER10',
      data: {'name': 'Jana', 'email': 'jana@example.org'},
    );
    final sameOrder = OrderModel(
      id: 10,
      orderSymbol: 'ORDER10',
      data: {'name': 'Jana', 'email': 'jana@example.org'},
    );
    // Equal display text must not merge distinct orders.
    final otherOrder = OrderModel(
      id: 11,
      orderSymbol: 'ORDER10',
      data: {'name': 'Jana', 'email': 'jana@example.org'},
    );
    final items = [
      TicketModel(id: 1, ticketSymbol: 'TICKET1', relatedOrder: order),
      TicketModel(id: 2, ticketSymbol: 'TICKET2', relatedOrder: sameOrder),
      TicketModel(id: 3, ticketSymbol: 'TICKET3', relatedOrder: otherOrder),
      TicketModel(id: 4, ticketSymbol: 'TICKET4'),
    ];
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: Scaffold(
        body: DataGridActionSummary<TicketModel>(
          items: items,
          itemsLabel: 'Vstupenky',
          message: 'Potvrdit storno vybraných vstupenek?',
          groupBy: (ticket) => ticket.relatedOrder,
        ),
      ),
    ));
    expect(find.text('Vstupenky: 4'), findsOneWidget);
    expect(find.text('Vstupenky: 2'), findsOneWidget);
    expect(find.text('Vstupenky: 1'), findsOneWidget);
    expect(find.text(order.toBasicString()), findsNWidgets(2));
    for (final item in items) {
      expect(find.text(item.toBasicString()), findsOneWidget);
    }
    expect(find.text('TICKET5'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shared confirmation shows action, supports cancel and confirm',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () async {
            result = await DataGridActionConfirmation.show<OrderModel>(
              context: context,
              title: 'Označit jako zaplacené',
              confirmButtonText: 'Zaplatit',
              itemsLabel: 'Objednávky',
              items: [
                OrderModel(
                  id: 10,
                  orderSymbol: 'ORDER10',
                  data: {
                    'name': 'Zákazník s dlouhým jménem',
                    'email': 'dlouhy.email.zakaznika@example.org',
                  },
                ),
              ],
            );
          },
          child: const Text('Open'),
        ),
      );
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Objednávky: 1'), findsOneWidget);
    expect(find.textContaining('ORDER10'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Zaplatit'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
  testWidgets(
      'Fakturoid deletion is opt-in and cancellation discards the choice',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? result;
    var hasFakturoid = true;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
        home: Scaffold(
            body: Builder(
                builder: (context) => ElevatedButton(
                      onPressed: () async {
                        result = await showOrderDeleteDialog(context,
                            orders: [OrderModel(id: 1, orderSymbol: 'ORDER1')],
                            hasFakturoid: hasFakturoid);
                      },
                      child: const Text('Open'),
                    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.delete));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(OrdersStrings.deleteFakturoidInvoice));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, CommonStrings.storno));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse);
    await tester.tap(find.text(OrdersStrings.deleteFakturoidInvoice));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.delete));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    hasFakturoid = false;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNothing);
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.delete));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });
}
