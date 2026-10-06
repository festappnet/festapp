import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/views/order_state_display.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';
import 'package:fstapp/components/email_delivery/email_delivery_model.dart';
import 'package:fstapp/components/single_data_grid/data_grid_strings.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

Map<String, dynamic> message(int id) => {
      'id': id,
      'message_id': 'message-$id',
      'order_id': 6500,
      'order_symbol': '7G4K9M2R6A',
      'message_kind': 'order_tickets',
      'state': 'unknown',
    };

void main() {
  test('history drains keyset pages while retaining the authorized order scope',
      () async {
    final calls = <Map<String, dynamic>>[];
    final rows = await EmailDeliveryModel.loadHistory((name, args) async {
      expect(name, 'get_email_delivery_page');
      calls.add(args);
      return args.containsKey('p_before')
          ? [message(2), message(1)]
          : List.generate(100, (i) => message(102 - i));
    }, {'p_occasion': 3, 'p_order': 7, 'p_orders_only': true});
    expect(rows.length, 102);
    expect(rows.map((r) => r.id).toSet().length, 102);
    expect(calls.last['p_before'], 3);
    expect(
        calls.every((p) =>
            p['p_occasion'] == 3 &&
            p['p_order'] == 7 &&
            p['p_orders_only'] == true &&
            p['p_limit'] == 100),
        isTrue);
  });
  test('a repeated cursor fails instead of looping or duplicating rows',
      () async {
    await expectLater(
        EmailDeliveryModel.loadHistory(
            (_, args) async => List.generate(100, (i) => message(100 - i)), {}),
        throwsFormatException);
  });

  testWidgets(
      'order history uses the standard read-only grid and redacted detail',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailDeliveryHistory(
      occasionId: 3,
      organizationId: 2,
      embedded: true,
      ordersOnly: true,
      read: (name, args) async {
        calls.add({'name': name, ...args});
        if (name == 'get_email_delivery_detail') {
          return {
            'message': {'tracking_policy': 'disabled'},
            'attempts': [
              {
                'state': 'unknown',
                'at': '2026-10-03',
                'error': 'transport_ambiguous'
              }
            ],
            'events': [],
          };
        }
        return [message(1)];
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls.single['p_orders_only'], true);
    expect(calls.single['p_occasion'], 3);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byType(TrinaGrid), findsOneWidget);
    final grid = tester.widget<SingleTableDataGrid<EmailDeliveryModel>>(
        find.byType(SingleTableDataGrid<EmailDeliveryModel>));
    final c = grid.controller;
    expect(
        c.columns.singleWhere((c) => c.field == EshopColumns.ORDER_SYMBOL).type,
        isA<TrinaColumnTypeText>());
    expect(find.text('7G4K9M2R6A'), findsOneWidget);
    expect(find.text('6500'), findsNothing);
    expect(find.text('6,500'), findsNothing);
    expect(find.byType(OrderStateDisplay), findsOneWidget);
    expect(c.firstColumnType, DataGridFirstColumn.none);
    expect(c.columns.every((column) => column.readOnly), isTrue);
    expect(c.actionsExtended!.isAddActionPossible!(), isFalse);
    for (final label in [
      CommonStrings.saveChanges,
      DataGridStrings.discardChanges
    ]) {
      expect(
          tester
              .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, label))
              .onPressed,
          isNull);
    }
    expect(c.hasPendingChanges, isFalse);
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('transport_ambiguous'), findsOneWidget);
    expect(calls.last['p_message'], 'message-1');
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.update));
    await tester.pumpAndSettle();
    expect(calls.last['p_orders_only'], true);
    expect(
        calls.where((p) => p['name'] == 'get_email_delivery_page').length, 2);
    expect(
        calls.every((p) => [
              'get_email_delivery_page',
              'get_email_delivery_detail'
            ].contains(p['name'])),
        isTrue);
  });

  testWidgets(
      'organization switch reloads grid and overview with the same scope',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: EmailDeliveryHistory(
      embedded: true,
      occasionId: 3,
      organizationId: 2,
      read: (name, args) async {
        calls.add({'name': name, ...args});
        return name == 'get_email_delivery_overview' ? <String, dynamic>{} : [];
      },
    ))));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(calls.length, 4);
    expect(
        calls
            .skip(2)
            .every((p) => p['p_occasion'] == null && p['p_organization'] == 2),
        isTrue);
  });

  testWidgets('changing scope during loading discards the old grid safely',
      (tester) async {
    final pending = Completer<List<dynamic>>();
    final calls = <int>[];
    Future<dynamic> read(String name, Map<String, dynamic> args) async {
      calls.add(args['p_occasion'] as int);
      return args['p_occasion'] == 3 ? pending.future : [message(2)];
    }

    Widget page(int occasion) => MaterialApp(
        home: Scaffold(
            body: EmailDeliveryHistory(
                embedded: true,
                ordersOnly: true,
                occasionId: occasion,
                read: read)));
    await tester.pumpWidget(page(3));
    await tester.pump();
    await tester.pumpWidget(page(4));
    await tester.pumpAndSettle();
    pending.complete([message(1)]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final c = tester
        .widget<SingleTableDataGrid<EmailDeliveryModel>>(
            find.byType(SingleTableDataGrid<EmailDeliveryModel>))
        .controller;
    expect(c.rows.single.cells['id']!.value, 2);
    expect(calls, [3, 4]);
  });
}
