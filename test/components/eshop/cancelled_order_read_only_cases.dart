import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_columns.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:trina_grid/trina_grid.dart';

class _Translations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('assets/translations/cs.json').readAsStringSync())
          as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('cancelled rows reject editing and disable product actions',
      (tester) async {
    await EasyLocalization.ensureInitialized();
    tester.view.physicalSize = const Size(3000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late TrinaGridStateManager manager;
    final rows = <TrinaRow>[];
    for (final entry in [
      ('ordered', 'ordered'),
      ('storno', 'storno'),
      ('storno', 'sent')
    ]) {
      final index = rows.length;
      rows.add(TrinaRow(cells: {
        EshopColumnIds.ORDER_MODEL_REFERENCE:
            TrinaCell(value: OrderModel(state: entry.$1)),
        EshopColumnIds.ORDER_STATE:
            TrinaCell(value: OrderModel.formatState(entry.$1)),
        EshopColumnIds.TICKET_STATE:
            TrinaCell(value: OrderModel.formatState(entry.$2)),
        EshopColumnIds.TICKET_PRODUCTS_EDIT: TrinaCell(value: ''),
        EshopColumnIds.ORDER_NOTE_HIDDEN: TrinaCell(value: 'order note $index'),
        EshopColumnIds.TICKET_NOTE_HIDDEN: TrinaCell(value: 'ticket note $index'),
        'response': TrinaCell(value: 'response $index'),
      }));
    }
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'unused',
      startLocale: const Locale('cs'),
      assetLoader: _Translations(),
      child: Builder(
          builder: (localizedContext) => MaterialApp(
                locale: localizedContext.locale,
                supportedLocales: localizedContext.supportedLocales,
                localizationsDelegates: localizedContext.localizationDelegates,
                home: Scaffold(body: Builder(builder: (context) {
                  final columns = EshopColumns.generateColumns(context, [
                    EshopColumnIds.ORDER_STATE,
                    EshopColumnIds.TICKET_STATE,
                    EshopColumnIds.TICKET_PRODUCTS_EDIT,
                    EshopColumnIds.ORDER_NOTE_HIDDEN,
                    EshopColumnIds.TICKET_NOTE_HIDDEN,
                  ]);
                  columns.add(EshopColumns.genericTextColumn(
                      'Response', 'response',
                      enableEditing: true));
                  for (final column in columns) {
                    column.width = 400;
                  }
                  return TrinaGrid(
                      columns: columns,
                      rows: rows,
                      onLoaded: (event) => manager = event.stateManager);
                })),
              )),
    ));
    await tester.pumpAndSettle();
    final buttons = tester
        .widgetList<ElevatedButton>(
            find.widgetWithIcon(ElevatedButton, Icons.category))
        .toList();
    expect(buttons, hasLength(3));
    expect(buttons[0].onPressed, isNotNull);
    expect(buttons[1].onPressed, isNull);
    expect(buttons[2].onPressed, isNull);
    for (final field in [
      EshopColumnIds.ORDER_NOTE_HIDDEN,
      EshopColumnIds.TICKET_NOTE_HIDDEN,
      'response'
    ]) {
      for (var index = 1; index < rows.length; index++) {
        final cell = rows[index].cells[field]!;
        final before = cell.value;
        manager.setCurrentCell(cell, index);
        manager.setEditing(true);
        expect(manager.isEditing, isFalse);
        manager.changeCellValue(cell, 'forbidden change');
        expect(cell.value, before);
      }
      final active = rows[0].cells[field]!;
      manager.setCurrentCell(active, 0);
      manager.setEditing(true);
      expect(manager.isEditing, isTrue);
      manager.setEditing(false);
      manager.changeCellValue(active, 'allowed change');
      expect(active.value, 'allowed change');
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
