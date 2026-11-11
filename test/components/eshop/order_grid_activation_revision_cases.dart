import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/components/eshop/order_symbol_cell.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

class _OrderRow implements ITrinaRowModel {
  const _OrderRow(this.id);
  @override
  final int id;
  @override
  TrinaRow toTrinaRow(BuildContext context) => TrinaRow(
    cells: {
      'id': TrinaCell(value: id),
      'customer': TrinaCell(value: 'Customer $id'),
      'note': TrinaCell(value: 'Note $id'),
      'symbol': TrinaCell(value: 'ORDER-$id'),
    },
  );
  @override
  Future<void> deleteMethod(BuildContext context) async {}
  @override
  Future<void> updateMethod(BuildContext context) async {}
  @override
  String toBasicString() => 'Order $id';
}

void main() {
  WidgetEnvironmentFixture.register();
  late SingleDataGridController<_OrderRow> controller;
  late List<int> activated;
  var escaped = 0;

  Future<void> open(WidgetTester tester) async {
    activated = [];
    escaped = 0;
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    final environment = WidgetEnvironmentFixture(
      locale: const Locale('en'),
      translations: jsonDecode(
        File('assets/translations/en.json').readAsStringSync(),
      ) as Map<String, dynamic>,
    );
    var created = false;
    await environment.pumpWidget(
      tester,
      MaterialApp(
        builder: DependencyMaterialBridge.builder,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              if (!created) {
                created = true;
                controller = SingleDataGridController<_OrderRow>(
                  context: context,
                  loadData: () async => [
                    const _OrderRow(1),
                    const _OrderRow(2),
                  ],
                  fromPlutoJson: (json) => _OrderRow(json['id'] as int),
                  firstColumnType: DataGridFirstColumn.check,
                  // Orders project SQL id to a differently named grid cell.
                  idColumn: 'databaseId',
                  onRowActivate: (row) => activated.add(row.id),
                  columns: [
                    TrinaColumn(
                      title: 'ID',
                      field: 'id',
                      width: 90,
                      readOnly: true,
                      type: TrinaColumnType.number(),
                    ),
                    TrinaColumn(
                      title: 'Customer',
                      field: 'customer',
                      width: 220,
                      readOnly: true,
                      type: TrinaColumnType.text(),
                    ),
                    TrinaColumn(
                      title: 'Note',
                      field: 'note',
                      width: 220,
                      type: TrinaColumnType.text(),
                    ),
                    TrinaColumn(
                      title: 'Symbol',
                      field: 'symbol',
                      width: 240,
                      readOnly: true,
                      type: TrinaColumnType.text(),
                      renderer: (cell) => OrderSymbolCell(
                        symbol: cell.cell.value as String,
                        onOpen: () =>
                            activated.add(cell.row.cells['id']!.value as int),
                      ),
                    ),
                  ],
                );
              }
              return SingleTableDataGrid(controller, onEscape: () => escaped++);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.stateManager.rows, hasLength(2));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.activeDetailRowId.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }

  Finder rowOutline(int id) {
    final row = controller.stateManager.rows.firstWhere(
      (row) => row.cells['id']!.value == id,
    );
    return find.byKey(ValueKey('grid-row-change-${row.key}'));
  }

  Future<void> doubleTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(finder, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'readonly double click opens its order; single click, checkbox and editing do not',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Customer 1'));
      await tester.pumpAndSettle();
      expect(activated, isEmpty);
      await doubleTap(tester, find.text('Customer 2'));
      expect(activated, [2]);
      activated.clear();

      final checkbox = find.descendant(
        of: rowOutline(1),
        matching: find.byType(TrinaScaledCheckbox),
      );
      expect(checkbox, findsOneWidget);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(controller.stateManager.rows.first.checked, isTrue);
      expect(activated, isEmpty);
      await doubleTap(tester, checkbox);
      expect(activated, isEmpty);

      await doubleTap(tester, find.text('Note 2'));
      expect(
        controller.stateManager.currentCell,
        same(controller.stateManager.rows[1].cells['note']),
      );
      expect(activated, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'symbol opens on one click while its clipboard action only copies',
    (tester) async {
      await open(tester);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData')
            copied = (call.arguments as Map)['text'] as String;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'ORDER-1'));
      await tester.pumpAndSettle();
      expect(activated, [1]);
      final symbol = find.ancestor(
        of: find.text('ORDER-2'),
        matching: find.byType(OrderSymbolCell),
      );
      await tester.tap(
        find.descendant(of: symbol, matching: find.byIcon(Icons.copy)),
      );
      await tester.pumpAndSettle();
      expect(copied, 'ORDER-2');
      expect(activated, [1]);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'opened order outline spans the row after current cell moves to another order',
    (tester) async {
      await open(tester);
      controller.activeDetailRowId.value = 1;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer 2'));
      await tester.pumpAndSettle();
      expect(controller.stateManager.currentRow?.cells['id']!.value, 2);
      final first = tester.widget<DecoratedBox>(rowOutline(1));
      final second = tester.widget<DecoratedBox>(rowOutline(2));
      final activeBorder =
          (first.decoration as BoxDecoration).border! as Border;
      final otherBorder =
          (second.decoration as BoxDecoration).border! as Border;
      for (final side in [
        activeBorder.left,
        activeBorder.top,
        activeBorder.right,
        activeBorder.bottom,
      ]) {
        expect(side.width, greaterThan(0));
        expect(side.color, isNot(Colors.transparent));
      }
      expect(otherBorder.top.color, Colors.transparent);
      expect(tester.getSize(rowOutline(1)).width, greaterThan(700));
      expect(activated, isEmpty);
      controller.activeDetailRowId.value = null;
      await tester.pumpAndSettle();
      final cleared =
          (tester.widget<DecoratedBox>(rowOutline(1)).decoration
                      as BoxDecoration)
                  .border!
              as Border;
      expect(cleared.top.color, Colors.transparent);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
  testWidgets(
    'modal Escape takes precedence over grid detail close and an active cell keeps its own Escape',
    (tester) async {
      await open(tester);
      var lateEscapes = 0;
      KeyEventResult lateHandler(KeyEvent event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          lateEscapes++;
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }

      FocusManager.instance.addLateKeyEventHandler(lateHandler);
      addTearDown(
        () => FocusManager.instance.removeLateKeyEventHandler(lateHandler),
      );
      await tester.tap(find.text('Customer 1'));
      final context = tester.element(find.text('Customer 1'));
      showDialog<void>(
        context: context,
        builder: (_) => AppAlertDialog(title: const Text('Payment modal')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Payment modal'), findsNothing);
      expect(escaped, 0);
      expect(lateEscapes, 0);
      await tester.tap(find.text('Customer 1'), kind: PointerDeviceKind.mouse);
      controller.stateManager.gridFocusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(controller.stateManager.gridFocusNode.hasPrimaryFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(escaped, 1);
      controller.stateManager.setCurrentCell(
        controller.stateManager.rows.first.cells['note'],
        0,
      );
      controller.stateManager.setEditing(true);
      await tester.pumpAndSettle();
      expect(controller.stateManager.isEditing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.stateManager.isEditing, isFalse);
      expect(escaped, 1);
      expect(lateEscapes, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
