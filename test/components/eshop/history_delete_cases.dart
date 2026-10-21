import 'package:timezone/timezone.dart' as fixtureTimezone;
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/forms/models/form_editor_draft.dart';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/order_grid_filters.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as zones;

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync());
}

void main() {
  testWidgets(
      'manager history grid deletes real cancelled history, not current-state projections',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    if (!fixtureTimezone.timeZoneDatabase.isInitialized) {
      zones.initializeTimeZones();
    }
    final previousZone = fixtureTimezone.local;
    addTearDown(() => fixtureTimezone.setLocalLocation(previousZone));
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final order = OrderModel(id: 1, state: 'storno', orderSymbol: 'HISTORY1')
      ..form = FormEditorDraft(id: 1, title: 'Přihláška').toBundle();
    final records = [
      OrderHistoryModel(id: 10, state: 'ordered', orderModel: order),
      OrderHistoryModel(id: 11, state: 'storno', orderModel: order),
      OrderHistoryModel.fromOrderModel(order),
    ];
    late SingleDataGridController<OrderHistoryModel> grid;
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'unused',
      assetLoader: _Translations(),
      child: MaterialApp(home: Builder(builder: (context) {
        expect(
            order.toTrinaRow(context).cells[EshopColumnIds.ORDER_FORM]!.value,
            'Přihláška');
        expect(
            records.first
                .toTrinaRow(context)
                .cells[EshopColumnIds.ORDER_FORM]!
                .value,
            'Přihláška');
        grid = SingleDataGridController<OrderHistoryModel>(
          context: context,
          loadData: () async => records,
          fromPlutoJson: OrderHistoryModel.fromPlutoJson,
          idColumn: EshopColumnIds.HISTORY_ID,
          firstColumnType: DataGridFirstColumn.delete,
          actionsExtended: DataGridActionsController(
            isAddActionPossible: () => false,
            canDeleteRow: OrderGridFilters.historyCanBeDeleted,
          ),
          columns: EshopColumns.generateColumns(context, [
            EshopColumnIds.HISTORY_ID,
            EshopColumnIds.HISTORY_MODEL_REFERENCE,
            EshopColumnIds.HISTORY_ORDER_SYMBOL,
            EshopColumnIds.HISTORY_STATE,
          ]),
        );
        return Scaffold(body: SingleTableDataGrid(grid));
      })),
    ));
    await tester.pumpAndSettle();
    final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete_forever);
    expect(deleteButtons, findsNWidgets(3));
    expect(tester.widget<IconButton>(deleteButtons.at(0)).onPressed, isNotNull);
    expect(tester.widget<IconButton>(deleteButtons.at(1)).onPressed, isNotNull);
    expect(tester.widget<IconButton>(deleteButtons.at(2)).onPressed, isNull);
    await tester.tap(deleteButtons.at(0));
    await tester.pumpAndSettle();
    expect(grid.deletedRows, contains(grid.rows.first));
    expect(grid.deletedRows.length, 1);
    expect(order.state, 'storno');
    expect(grid.deletedRows, isNot(contains(grid.rows.last)));
    expect(tester.takeException(), isNull);
    final context =
        tester.element(find.byType(SingleTableDataGrid<OrderHistoryModel>));
    await expectLater(records.last.deleteMethod(context), throwsStateError);
  });
}
