import 'package:fstapp/widgets/dependency_material_bridge.dart';
import '../../support/fixtures/localization_log_fixture.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

class _Row extends ITrinaRowModel {
  @override
  final int id;
  _Row(this.id);
  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(cells: {
        'id': TrinaCell(value: id),
        'value': TrinaCell(value: 'server $id')
      });
  @override
  Future<void> deleteMethod(BuildContext context) async {}
  @override
  Future<void> updateMethod(BuildContext context) async {}
  @override
  String toBasicString() => '$id';
}

void main() {
  // This suite intentionally uses untranslated key fallback (no catalog).
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  for (final recoverOnReturn in [false, true]) {
    testWidgets(
        'failed initial load recovers via ${recoverOnReturn ? 'tab return' : 'retry'}',
        (tester) async {
      late SingleDataGridController<_Row> grid;
      late TabController tabs;
      var calls = 0;
      await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
        tabs = TabController(length: 2, vsync: tester);
        grid = SingleDataGridController(
            context: context,
            loadData: () async {
              if (++calls == 1) throw StateError('initial request failed');
              return [_Row(42)];
            },
            fromPlutoJson: (json) => _Row(json['id']),
            firstColumnType: DataGridFirstColumn.none,
            idColumn: 'id',
            columns: [
              TrinaColumn(
                  title: 'id', field: 'id', type: TrinaColumnType.number()),
              TrinaColumn(
                  title: 'value', field: 'value', type: TrinaColumnType.text()),
            ]);
        return Scaffold(
            body: TabBarView(controller: tabs, children: [
          AdminTabActivity(
              controller: tabs, index: 0, child: SingleTableDataGrid(grid)),
          AdminTabActivity(
              controller: tabs, index: 1, child: const Text('Other')),
        ]));
      })));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Common.unexpectedError'), findsOneWidget);
      if (recoverOnReturn) {
        tabs.index = 1;
        await tester.pumpAndSettle();
        tabs.index = 0;
      } else {
        await tester.tap(find.text('Common.retry'));
      }
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(grid.isGridLoaded, isTrue);
      expect(grid.rows.single.cells['id']!.value, 42);
      expect(find.text('DataGrid.refreshPending'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      tabs.dispose();
    });
  }
  testWidgets(
      'return reloads automatically; dirty grid retained and not fetched',
      (tester) async {
    late TabController tabs;
    late SingleDataGridController<_Row> grid;
    int calls = 0;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      tabs = TabController(length: 2, vsync: tester);
      grid = SingleDataGridController(
          context: context,
          loadData: () async {
            calls++;
            return [_Row(calls)];
          },
          fromPlutoJson: (json) => _Row(json['id']),
          firstColumnType: DataGridFirstColumn.none,
          idColumn: 'id',
          columns: [
            TrinaColumn(
                title: 'id', field: 'id', type: TrinaColumnType.number()),
            TrinaColumn(
                title: 'value', field: 'value', type: TrinaColumnType.text()),
          ]);
      return Scaffold(
          body: TabBarView(controller: tabs, children: [
        AdminTabActivity(
            controller: tabs, index: 0, child: SingleTableDataGrid(grid)),
        AdminTabActivity(
            controller: tabs, index: 1, child: const Text('Other')),
      ]));
    })));
    await tester.pumpAndSettle();
    expect(calls, 1);
    tabs.index = 1;
    await tester.pumpAndSettle();
    tabs.index = 0;
    await tester.pumpAndSettle();
    expect(calls, 2);
    grid.updatedRows.add(grid.rows.first);
    grid.rows.first.cells['value']!.value = 'draft';
    tabs.index = 1;
    await tester.pumpAndSettle();
    tabs.index = 0;
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(grid.rows.first.cells['value']!.value, 'draft');
    expect(grid.updatedRows, isNotEmpty);
    await tester.pumpWidget(const SizedBox());
    tabs.dispose();
  });
  testWidgets(
      'edit started during fetch prevents data replacement; sort and width survive clean refresh',
      (tester) async {
    late SingleDataGridController<_Row> grid;
    Completer<List<_Row>>? pending;
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder, home: Builder(builder: (context) {
      grid = SingleDataGridController(
          context: context,
          loadData: () async {
            if (pending != null) return await pending.future;
            return [_Row(1), _Row(2)];
          },
          fromPlutoJson: (json) => _Row(json['id']),
          firstColumnType: DataGridFirstColumn.none,
          idColumn: 'id',
          columns: [
            TrinaColumn(
                title: 'id',
                field: 'id',
                type: TrinaColumnType.number(),
                width: 170),
            TrinaColumn(
                title: 'value', field: 'value', type: TrinaColumnType.text()),
          ]);
      return Scaffold(body: SingleTableDataGrid(grid));
    })));
    await tester.pumpAndSettle();
    pending = Completer<List<_Row>>();
    final refreshing = grid.reloadIfClean();
    grid.updatedRows.add(grid.rows.first);
    grid.rows.first.cells['value']!.value = 'typed during request';
    pending.complete([_Row(3)]);
    expect(await refreshing, false);
    expect(grid.rows.first.cells['value']!.value, 'typed during request');
    grid.updatedRows.clear();
    pending = null;
    grid.stateManager.sortDescending(grid.columns.first);
    expect(await grid.reloadIfClean(), true);
    await tester.pumpAndSettle();
    expect(grid.columns.first.width, 170);
    expect(grid.columns.first.sort.isDescending, true);
    expect(grid.stateManager.rows.first.cells['id']!.value, 2);
  });
}
