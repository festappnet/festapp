import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

class _OrderRow implements ITrinaRowModel {
  final OrderModel order;
  final List<int> deleted;
  _OrderRow(this.order, this.deleted);
  @override
  int get id => order.id!;
  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(cells: {
        'id': TrinaCell(value: id),
        'state': TrinaCell(value: order.state),
        EshopColumns.ORDER_MODEL_REFERENCE: TrinaCell(value: order),
      });
  @override
  Future<void> deleteMethod(BuildContext context) async => deleted.add(id);
  @override
  Future<void> updateMethod(BuildContext context) async {}
  @override
  String toBasicString() => 'Order $id';
}

void main() {
  testWidgets(
      'ordinary ordered/sent trash is clickable and deletion still requires confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final deleted = <int>[];
    final orders = [
      for (final state in [
        'ordered',
        'sent',
        'paid',
        'storno',
        'waitlisted',
        'preparing_payment'
      ])
        OrderModel(
            id: [
                  'ordered',
                  'sent',
                  'paid',
                  'storno',
                  'waitlisted',
                  'preparing_payment'
                ].indexOf(state) +
                1,
            state: state),
      OrderModel.fromJson({
        'id': 7,
        'state': 'sent',
        'waitlistSummary': {
          'counts': {'accepted': 1}
        }
      }),
    ];
    final models = orders.map((order) => _OrderRow(order, deleted)).toList();
    late SingleDataGridController<_OrderRow> grid;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      grid = SingleDataGridController<_OrderRow>(
        context: context,
        loadData: () async => models,
        fromPlutoJson: (json) => models.singleWhere((m) => m.id == json['id']),
        firstColumnType: DataGridFirstColumn.deleteAndCheck,
        idColumn: 'id',
        actionsExtended: DataGridActionsController(
          areAllActionsEnabled: () => true,
          isAddActionPossible: () => false,
          canDeleteRow: OrderGridFilters.orderCanBeDeleted,
        ),
        columns: [
          TrinaColumn(title: 'ID', field: 'id', type: TrinaColumnType.number()),
          TrinaColumn(
              title: 'State', field: 'state', type: TrinaColumnType.text()),
          TrinaColumn(
              title: '',
              field: EshopColumns.ORDER_MODEL_REFERENCE,
              type: TrinaColumnType.text(),
              hide: true),
        ],
      );
      return SingleTableDataGrid(grid);
    }))));
    await tester.pumpAndSettle();
    final buttons = tester
        .widgetList<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_forever))
        .toList();
    expect(buttons, hasLength(7));
    for (var i = 0; i < 4; i++) {
      expect(buttons[i].onPressed, isNotNull,
          reason: '${orders[i].state} ordinary order must be deletable');
    }
    for (var i = 4; i < 7; i++) {
      expect(buttons[i].onPressed, isNull,
          reason:
              'Waiting, preparing and offer-history orders remain protected');
    }
    await tester.tap(find.byIcon(Icons.delete_forever).first);
    await tester.pumpAndSettle();
    expect(grid.deletedRows, hasLength(1));
    expect(deleted, isEmpty);
    await tester
        .tap(find.widgetWithText(ElevatedButton, CommonStrings.saveChanges));
    await tester.pumpAndSettle();
    expect(find.text(CommonStrings.confirmRemoval), findsOneWidget);
    expect(deleted, isEmpty);
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.delete));
    await tester.pumpAndSettle();
    expect(deleted, [1]);
  });
}
