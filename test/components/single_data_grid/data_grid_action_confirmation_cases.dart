import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';

void main() {
  testWidgets('ticket row preserves labels, parent and edited note',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
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
      row.cells[EshopColumns.TICKET_NOTE_HIDDEN]!.value = 'Edited note';
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
    await tester.pumpWidget(MaterialApp(
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
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
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
}
