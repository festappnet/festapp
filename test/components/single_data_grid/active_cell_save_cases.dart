import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

import 'data_grid_dirty_actions_cases.dart' show RowModel;

void main() {
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final customAction in [false, true]) {
    testWidgets(
      'save commits the active cell draft before serializing a new row (custom=$customAction)',
      (tester) async {
        late SingleDataGridController<RowModel> controller;
        String? savedValue;
        await tester.pumpWidget(
          MaterialApp(
            builder: DependencyMaterialBridge.builder,
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  controller = SingleDataGridController<RowModel>(
                    context: context,
                    loadData: () async => [],
                    fromPlutoJson: (json) {
                      savedValue = json['value'] as String;
                      return RowModel(json['id'] as int);
                    },
                    getNewObject: () => RowModel(-1),
                    idColumn: 'id',
                    firstColumnType: DataGridFirstColumn.none,
                    actionsExtended: customAction
                        ? DataGridActionsController(
                            saveAction: DataGridAction(
                              action: (grid, [original]) async {
                                savedValue =
                                    grid
                                            .stateManager
                                            .rows
                                            .single
                                            .cells['value']!
                                            .value
                                        as String;
                              },
                            ),
                          )
                        : null,
                    columns: [
                      TrinaColumn(
                        title: 'ID',
                        field: 'id',
                        type: TrinaColumnType.number(),
                      ),
                      TrinaColumn(
                        title: 'Email',
                        field: 'value',
                        type: TrinaColumnType.text(),
                      ),
                    ],
                  );
                  return SingleTableDataGrid(controller);
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(ElevatedButton, CommonStrings.add),
        );
        await tester.pumpAndSettle();
        final row = controller.stateManager.rows.single;
        controller.stateManager.setKeepFocus(true);
        controller.stateManager.gridFocusNode.requestFocus();
        controller.stateManager.setCurrentCell(row.cells['value'], 0);
        controller.stateManager.setEditing(true);
        await tester.pumpAndSettle();
        final editor = find.byWidgetPredicate(
          (w) =>
              w is EditableText &&
              identical(
                w.controller,
                controller.stateManager.textEditingController,
              ),
        );
        expect(editor, findsOneWidget);
        await tester.enterText(editor, 'jana@example.invalid');
        expect(
          controller.stateManager.textEditingController!.text,
          'jana@example.invalid',
        );
        await tester.pump();
        await tester.tap(
          find.widgetWithText(ElevatedButton, CommonStrings.saveChanges),
        );
        await tester.pumpAndSettle();
        expect(savedValue, 'jana@example.invalid');
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
