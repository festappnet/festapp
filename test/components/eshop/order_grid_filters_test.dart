import 'package:fstapp/components/eshop/order_symbol_cell.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';

void main() {
  test('canonical sequence is readonly; legacy DTO remains readable', () {
    final order = OrderModel.fromCanonicalJson({
      'id': 5,
      'order_symbol': '7G4K9M2R6A',
      'order_sequence': 10,
    });
    expect(order.orderSequence, 10);
    expect(order.toJson().containsKey('order_sequence'), false);
    expect(order.toBasicString(), '7G4K9M2R6A');
    expect(OrderHistoryModel.fromOrderModel(order).orderSequence, 10);
    expect(OrderModel.fromJson({'id': 5}).orderSequence, null);
    expect(() => OrderModel.fromCanonicalJson({'id': 5}), throwsStateError);
  });

  testWidgets(
    'real filter button composes native filters, retains drafts, clears hidden selection, exports same rows and refreshes',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late SingleDataGridController<OrderModel> grid;
      var calls = 0;
      List<int?> submitted = [];
      final orders = [
        OrderModel(
          id: 1,
          orderSequence: 10,
          orderSymbol: '7W4M9W2M6W',
          state: 'paid',
          noteHidden: 'keep',
        ),
        OrderModel(
          id: 2,
          orderSequence: 2,
          orderSymbol: '8A4C9E2F6G',
          state: 'storno',
        ),
        OrderModel(
          id: 3,
          orderSequence: 3,
          orderSymbol: '9A4C9E2F6G',
          state: 'expired',
        ),
        OrderModel(
          id: 4,
          orderSequence: 4,
          orderSymbol: '1A4C9E2F6G',
          state: null,
        ),
      ];
      for (final order in orders) { order.paymentInfoModel = PaymentInfoModel(); }
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              grid = SingleDataGridController<OrderModel>(
                context: context,
                loadData: () async {
                  calls++;
                  return orders;
                },
                fromPlutoJson: OrderModel.fromPlutoJson,
                firstColumnType: DataGridFirstColumn.check,
                idColumn: EshopColumns.ORDER_ID,
                additionalRowPredicate: OrderGridFilters.orderIsNonCancelled,
                headerFilterBuilder: OrderGridFilters.filterButton,
                actionsExtended: DataGridActionsController(
                  isAddActionPossible: () => false,
                ),
                headerChildren: [
                  DataGridAction(
                    name: 'Submit visible',
                    requiresSelection: true,
                    action: (controller, [_]) => submitted = controller
                        .visibleCheckedRows
                        .map(
                          (r) => r.cells[EshopColumns.ORDER_ID]!.value as int,
                        )
                        .toList(),
                  ),
                ],
                columns: [
                  TrinaColumn(
                    title: 'Id',
                    field: EshopColumns.ORDER_ID,
                    type: TrinaColumnType.number(),
                    hide: true,
                  ),
                  EshopColumns.orderSequenceColumn(),
                  EshopColumns.orderSymbolColumn(),
                  TrinaColumn(
                    title: 'Note',
                    field: EshopColumns.ORDER_NOTE_HIDDEN,
                    type: TrinaColumnType.text(),
                  ),
                ],
              );
              return Scaffold(body: SingleTableDataGrid(grid));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(grid.additionalFilterCount, 3);
      expect(grid.columns.firstWhere((c) => c.field == EshopColumns.ORDER_SEQUENCE).width, 90);
      expect(grid.columns.firstWhere((c) => c.field == EshopColumns.ORDER_SYMBOL).width, 154);
      expect(grid.stateManager.rows.length, 4);
      final active = grid.rows[0], cancelled = grid.rows[1];
      active.cells[EshopColumns.ORDER_NOTE_HIDDEN]!.value = 'draft';
      active.setState(TrinaRowState.updated);
      grid.updatedRows.add(active);
      grid.stateManager.setRowChecked(active, true);
      grid.stateManager.setRowChecked(cancelled, true);
      await tester.tap(find.byKey(const ValueKey("onlyNonCancelled")));
      await tester.pumpAndSettle();
      expect(grid.stateManager.rows.length, 3);
      expect(cancelled.checked, false);
      expect(active.state, TrinaRowState.updated);
      expect(active.cells[EshopColumns.ORDER_NOTE_HIDDEN]!.value, 'draft');
      expect(grid.updatedRows, contains(active));
      expect(calls, 1);
      await tester.tap(find.text('Submit visible'));
      expect(submitted, [1]);
      grid.stateManager.setFilterWithFilterRows([
        FilterHelper.createFilterRow(
          columnField: EshopColumns.ORDER_SYMBOL,
          filterType: const TrinaFilterTypeStartsWith(),
          filterValue: '8',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(grid.additionalFilterCount, 0);
      expect(grid.stateManager.rows, isEmpty);
      expect(active.checked, false);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Submit visible'),
            )
            .onPressed,
        null,
      );
      await tester.tap(find.byKey(const ValueKey("onlyNonCancelled")));
      await tester.pumpAndSettle();
      expect(grid.stateManager.rows, [cancelled]);
      expect(grid.additionalFilterCount, 0);
      final csv = await TrinaGridExportCsv().export(
        stateManager: grid.stateManager,
        includeHeaders: true,
      );
      expect(csv, contains('8A4C9E2F6G'));
      expect(csv, isNot(contains('7W4M9W2M6W')));
      grid.stateManager.setFilterWithFilterRows([]);
      await tester.pumpAndSettle();
      grid.stateManager.sortAscending(
        grid.columns.firstWhere((c) => c.field == EshopColumns.ORDER_SEQUENCE),
      );
      expect(
        grid.stateManager.rows.map(
          (r) => r.cells[EshopColumns.ORDER_SEQUENCE]!.value,
        ),
        [2, 3, 4, 10],
      );
      expect(active.state, TrinaRowState.updated);
      expect(await grid.reloadIfClean(), false);
      grid.updatedRows.clear();
      grid.stateManager.setEditing(false);
      await tester.tap(find.byKey(const ValueKey("onlyNonCancelled")));
      await tester.pumpAndSettle();
      await grid.reloadData();
      await tester.pumpAndSettle();
      expect(grid.additionalFilterEnabled, true);
      expect(grid.additionalFilterCount, 3);
      expect(grid.stateManager.rows.length, 3);
      expect(grid.stateManager.rows.map((r) => r.cells[EshopColumns.ORDER_SEQUENCE]!.value), [3, 4, 10]);
      grid.stateManager.setFilterWithFilterRows([FilterHelper.createFilterRow(
          columnField: EshopColumns.ORDER_SYMBOL, filterValue: '7')]);
      await tester.pumpAndSettle();
      await grid.reloadData();
      await tester.pumpAndSettle();
      expect(grid.stateManager.filterRows.length, 1);
      expect(grid.stateManager.rows.length, 1);
      expect(grid.additionalFilterCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(grid.isGridLoaded, false);
    },
  );

  testWidgets('inline copy stays visible and gives themed feedback in light and dark mode', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    for (final brightness in [Brightness.light, Brightness.dark]) {
      final theme = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: brightness));
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: SizedBox(width: 180, height: 40,
          child: OrderSymbolCell(key: ValueKey(brightness), symbol: '9W9W9W9W9W')))));
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.text('9W9W9W9W9W'), findsOneWidget);
      expect(find.byType(PopupMenuButton<void>), findsNothing);
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pumpAndSettle();
      expect(copied, '9W9W9W9W9W');
      expect(find.byIcon(Icons.check), findsOneWidget);
      final style = tester.widget<IconButton>(find.byType(IconButton)).style!;
      expect(style.foregroundColor!.resolve({}), theme.colorScheme.onPrimary);
      expect(style.backgroundColor!.resolve({}), theme.colorScheme.primary);
      await tester.pumpWidget(MaterialApp(theme: theme, home: Scaffold(body: SizedBox(width: 180, height: 40,
          child: OrderSymbolCell(key: ValueKey(brightness), symbol: '1A2B3C4D5E')))));
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'ticket count excludes partial storno and cancelled parents, uses same parent sequence',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late SingleDataGridController<TicketModel> grid;
      final parent = OrderModel(id: 50, orderSequence: 7, state: 'paid');
      final cancelledParent = OrderModel(
        id: 60,
        orderSequence: 8,
        state: 'storno',
      );
      final tickets = [
        TicketModel(id: 1, state: 'used', relatedOrder: parent),
        TicketModel(id: 2, state: 'storno', relatedOrder: parent),
        TicketModel(id: 3, state: 'expired', relatedOrder: parent),
        TicketModel(id: 4, state: 'paid', relatedOrder: cancelledParent),
        TicketModel(id: 5, state: null, relatedOrder: parent),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              grid = SingleDataGridController<TicketModel>(
                context: context,
                loadData: () async => tickets,
                fromPlutoJson: TicketModel.fromPlutoJson,
                firstColumnType: DataGridFirstColumn.check,
                idColumn: EshopColumns.TICKET_ID,
                additionalRowPredicate: OrderGridFilters.ticketIsNonCancelled,
                headerFilterBuilder: OrderGridFilters.filterButton,
                columns: [
                  TrinaColumn(
                    title: 'Id',
                    field: EshopColumns.TICKET_ID,
                    type: TrinaColumnType.number(),
                  ),
                  TrinaColumn(
                    title: 'Sequence',
                    field: EshopColumns.ORDER_SEQUENCE,
                    type: TrinaColumnType.number(),
                  ),
                ],
              );
              return Scaffold(body: SingleTableDataGrid(grid));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(grid.additionalFilterCount, 3);
      expect(
        grid.rows
            .take(3)
            .map((r) => r.cells[EshopColumns.ORDER_SEQUENCE]!.value),
        [7, 7, 7],
      );
      await tester.tap(find.byKey(const ValueKey("onlyNonCancelled")));
      await tester.pumpAndSettle();
      expect(
        grid.stateManager.rows.map(
          (r) => r.cells[EshopColumns.TICKET_ID]!.value,
        ),
        [1, 3, 5],
      );
      parent.state = 'storno';
      await grid.reloadData();
      await tester.pumpAndSettle();
      expect(grid.additionalFilterCount, 0);
      expect(grid.stateManager.rows, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'wide symbol fits the shared width with normal and enlarged text',
    (tester) async {
      await tester.runAsync(() async {
      final font = FontLoader('RealRoboto')..addFont(Future.value(ByteData.sublistView(await File('test/fixtures/ticket_fonts/Roboto.ttf').readAsBytes())));
      await font.load();
    });
    for (final scale in [1.0, 1.3]) {
      await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'RealRoboto'),
        home: MediaQuery(data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(builder: (context) {
            final style = DefaultTextStyle.of(context).style.merge(TrinaGridStyleConfig.defaultLightCellTextStyle);
            final text = TextPainter(text: TextSpan(text: '9W9W9W9W9W', style: style),
              textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
            expect(text.width + 54, lessThanOrEqualTo(EshopColumns.orderSymbolColumn(context: context).width));
            text.dispose();
            return const SizedBox();
          }))));
    }
  });
}
