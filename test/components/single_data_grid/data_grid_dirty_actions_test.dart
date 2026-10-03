import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_strings.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

class RowModel implements ITrinaRowModel {
  @override
  final int id;
  RowModel(this.id);
  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(cells: {
        'id': TrinaCell(value: id),
        'value': TrinaCell(value: 'Original'),
      });
  @override
  Future<void> deleteMethod(BuildContext context) async {}
  @override
  Future<void> updateMethod(BuildContext context) async {}
  @override
  String toBasicString() => '$id';
}

void main() {
  testWidgets(
      'save and discard follow grid edits, additions, deletions and HTML drafts',
      (tester) async {
    late SingleDataGridController<RowModel> controller;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      controller = SingleDataGridController<RowModel>(
        context: context,
        loadData: () async => [RowModel(1)],
        fromPlutoJson: (json) => RowModel(json['id'] as int),
        getNewObject: () => RowModel(-1),
        idColumn: 'id',
        firstColumnType: DataGridFirstColumn.delete,
        columns: [
          TrinaColumn(title: 'ID', field: 'id', type: TrinaColumnType.number()),
          TrinaColumn(
              title: 'Value', field: 'value', type: TrinaColumnType.text())
        ],
      );
      return SingleTableDataGrid(controller);
    }))));
    await tester.pumpAndSettle();
    void enabled(bool expected) {
      for (final text in [
        CommonStrings.saveChanges,
        DataGridStrings.discardChanges
      ]) {
        final button = tester
            .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, text));
        expect(button.onPressed != null, expected, reason: text);
      }
    }

    enabled(false);
    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pumpAndSettle();
    enabled(true);
    await tester.tap(find.byIcon(Icons.delete_forever));
    await tester.pumpAndSettle();
    enabled(false);
    final row = controller.stateManager.rows.single;
    controller.stateManager.changeCellValue(row.cells['value']!, 'Changed');
    await tester.pumpAndSettle();
    enabled(true);
    await controller.reloadData();
    await tester.pumpAndSettle();
    enabled(false);
    await tester.tap(find.widgetWithText(ElevatedButton, CommonStrings.add));
    await tester.pumpAndSettle();
    enabled(true);
    await controller.reloadData();
    await tester.pumpAndSettle();
    enabled(false);
    var dirty = true;
    controller.htmlSave.registerActive('draft', () {}, isDirty: () => dirty);
    await tester.pumpAndSettle();
    enabled(true);
    dirty = false;
    controller.htmlSave.draftChanged();
    await tester.pumpAndSettle();
    enabled(false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
