import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/single_data_grid/data_grid_column_header.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:trina_grid/trina_grid.dart';

const help = 'Local explanation for the value.';
Finder get info => find.byIcon(Icons.info_outline);
Finder title(String text) => find.text(text, findRichText: true);

TrinaColumn column(String field, {double width = 220, bool checked = false}) =>
    TrinaColumn(
      title: field,
      field: field,
      type: TrinaColumnType.text(),
      width: width,
      minWidth: 20,
      enableRowChecked: checked,
    );

Future<TrinaGridStateManager> mountGrid(
  WidgetTester tester,
  List<TrinaColumn> columns, {
  Map<String, String> explanations = const {'Value': help},
  TrinaGridStyleConfig style = const TrinaGridStyleConfig(),
  double textScale = 1,
  double width = 750,
}) async {
  DataGridColumnHeader.install(columns, explanations, style);
  late TrinaGridStateManager manager;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 600),
          textScaler: TextScaler.linear(textScale),
        ),
        child: Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('Before grid')),
            SizedBox(
              width: width,
              height: 450,
              child: FocusTraversalGroup(
                policy: DataGridColumnHelpTraversalPolicy(),
                child: TrinaGrid(
                  columns: columns,
                  rows: [
                    for (final value in ['beta', 'alpha'])
                      TrinaRow(cells: {
                        for (final c in columns)
                          c.field: TrinaCell(value: value),
                      }),
                  ],
                  configuration: TrinaGridConfiguration(style: style),
                  onLoaded: (event) => manager = event.stateManager,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return manager;
}

Future<void> closeGrid(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('absent and blank help preserves the original columns',
      (tester) async {
    final columns = [column('Value', width: 30), column('Other', width: 30)];
    for (final explanations in <Map<String, String>>[
      {},
      {'Missing': help},
      {'Value': ''},
      {'Value': ' \n\t '},
    ]) {
      final manager =
          await mountGrid(tester, columns, explanations: explanations);
      expect(info, findsNothing);
      for (final c in columns) {
        expect(c.titleRenderer, isNull);
        expect(c.minWidth, 20);
        expect(c.width, 30);
      }
      final oldSort = columns.first.sort;
      manager.toggleSortColumn(columns.first);
      await tester.pumpAndSettle();
      expect(columns.first.sort, isNot(oldSort));
      await closeGrid(tester);
    }
  });

  testWidgets('hover, touch and mouse taps open help without sorting',
      (tester) async {
    final c = column('Value');
    await mountGrid(tester, [c, column('Other')]);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 550));
    await mouse.moveTo(tester.getCenter(info));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text(help), findsOneWidget);
    await mouse.moveTo(const Offset(700, 550));
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);

    await tester.tap(info); // Touch is the default pointer kind.
    await tester.pumpAndSettle();
    expect(find.text(help), findsOneWidget);
    expect(c.sort.isNone, isTrue);
    await tester.tapAt(const Offset(700, 550));
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);

    await mouse.moveTo(tester.getCenter(info));
    await mouse.down(tester.getCenter(info));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text(help), findsOneWidget);
    expect(c.sort.isNone, isTrue);
    await mouse.moveTo(const Offset(700, 550));
    await tester.tap(title('Value'));
    await tester.pumpAndSettle();
    expect(c.sort.isAscending, isTrue);
    expect(find.byIcon(Icons.sort), findsOneWidget);
    await tester.tap(title('Other'));
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await closeGrid(tester);
  });

  testWidgets('Tab, Enter, Space and scoped Escape operate the info button',
      (tester) async {
    final manager = await mountGrid(tester, [column('Value')]);
    final button = tester.widget<IconButton>(find.ancestor(
      of: info,
      matching: find.byType(IconButton),
    ));
    Focus.of(tester.element(find.text('Before grid'))).requestFocus();
    await tester.pump();
    // Traverse the real grid focus order rather than invoking onPressed.
    for (var i = 0; i < 12 && !button.focusNode!.hasFocus; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.pump();
    }
    expect(button.focusNode!.hasFocus, isTrue);
    for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(find.text(help), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(help), findsNothing);
    }
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Value: $help'), findsOneWidget);
    semantics.dispose();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(button.focusNode!.hasFocus, isFalse);
    manager.setEditing(true);
    await tester.pumpAndSettle();
    expect(manager.isEditing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(manager.isEditing, isFalse);
    expect(find.text(help), findsNothing);
    await closeGrid(tester);
  });

  testWidgets('narrow checked filtered headers keep controls and styled title',
      (tester) async {
    for (final style in [
      const TrinaGridStyleConfig(
        columnTextStyle: TextStyle(color: Colors.purple),
      ),
      const TrinaGridStyleConfig.dark(
        columnTextStyle: TextStyle(color: Colors.amber),
      ),
    ]) {
      final c = column('Value', width: 25, checked: true)
        ..title = 'A very long title that must be ellipsized'
        ..titleSpan = const TextSpan(text: 'Rich long title')
        ..titleTextAlign = TrinaColumnTextAlign.right;
      final longHelp =
          List.filled(35, 'Long explanation with wrapping.').join(' ');
      final manager = await mountGrid(tester, [c],
          explanations: {'Value': longHelp},
          style: style,
          width: 260,
          textScale: 2);
      final minimum = c.minWidth;
      final renderer = c.titleRenderer;
      DataGridColumnHeader.install([c], {'Value': longHelp}, style);
      expect(c.minWidth, minimum);
      expect(c.titleRenderer, renderer);
      expect(c.width, minimum);
      manager.setFilterWithFilterRows([
        FilterHelper.createFilterRow(
          columnField: c.field,
          filterType: const TrinaFilterTypeContains(),
          filterValue: 'a',
        ),
      ]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.descendant(
        of: find.byType(DataGridColumnHeader),
        matching: find.byType(Text),
      ));
      expect(text.textAlign, TextAlign.right);
      expect(text.style, style.columnTextStyle);
      await tester.tap(find.descendant(
        of: find.byType(DataGridColumnHeader),
        matching: find.byType(Checkbox),
      ));
      await tester.pumpAndSettle();
      expect(manager.rows.every((row) => row.checked == true), isTrue);
      final filter = find.descendant(
        of: find.byType(DataGridColumnHeader),
        matching: find.byIcon(style.filterIcon!.icon!),
      );
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(find.byType(TrinaGrid), findsNWidgets(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.text(longHelp), findsOneWidget);
      expect(tester.getSize(find.text(longHelp)).width, lessThanOrEqualTo(260));
      manager.resizeColumn(c, -1000);
      await tester.pumpAndSettle();
      expect(c.width, minimum);
      expect(tester.takeException(), isNull);
      await closeGrid(tester);
    }
  });

  testWidgets('context icon retains menu and resizing, title retains drag',
      (tester) async {
    final c = column('Value');
    final other = column('Other');
    final manager = await mountGrid(tester, [c, other]);
    final contextIcon = find.descendant(
      of: find.byType(DataGridColumnHeader),
      matching: find.byIcon(manager.style.columnContextIcon),
    );
    await tester.tap(contextIcon);
    await tester.pumpAndSettle();
    expect(find.text(manager.localeText.setFilter), findsOneWidget);
    await tester.tapAt(const Offset(700, 550));
    await tester.pumpAndSettle();
    final originalWidth = c.width;
    await tester.drag(contextIcon, const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(c.width, greaterThan(originalWidth));
    expect(c.sort.isNone, isTrue);
    final target = tester.getCenter(title('Other'));
    final infoStart = tester.getCenter(info);
    await tester.dragFrom(infoStart, target - infoStart);
    await tester.pumpAndSettle();
    expect(manager.columns.first, c);
    final nameStart = tester.getCenter(title('Value'));
    await tester.dragFrom(nameStart, target - nameStart);
    await tester.pumpAndSettle();
    expect(manager.columns.first, other);
    await closeGrid(tester);
  });

  testWidgets(
      'scroll, hide, removal and timeout clean up overlays; CSV is intact',
      (tester) async {
    final c = column('Value');
    final manager = await mountGrid(
        tester, [c, column('Other'), column('Third'), column('Fourth')],
        width: 450);
    final csv = await TrinaGridExportCsv().export(stateManager: manager);
    expect(csv, contains('Value'));
    expect(csv, isNot(contains(help)));
    await tester.tap(info);
    await tester.pumpAndSettle();
    manager.scroll.horizontal!.jumpTo(40);
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);
    await tester.tap(info);
    await tester.pumpAndSettle();
    manager.hideColumn(c, true);
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);
    expect(info, findsNothing);
    manager.hideColumn(c, false);
    manager.scroll.horizontal!.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);
    await tester.tap(info);
    await tester.pumpAndSettle();
    manager.removeColumns([c]);
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);
    expect(info, findsNothing);
    await closeGrid(tester);
  });

  testWidgets(
      'wrapper rebuild and forceReload install exactly once on new columns',
      (tester) async {
    late SingleDataGridController<_MemoryRow> controller;
    final explanations = {'Value': help};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        controller = SingleDataGridController<_MemoryRow>(
          context: context,
          loadData: () async => [_MemoryRow()],
          fromPlutoJson: (_) => _MemoryRow(),
          firstColumnType: DataGridFirstColumn.none,
          idColumn: 'Value',
          columns: [column('Value')],
          columnHelp: explanations,
        );
        return _WrapperHost(controller: controller);
      })),
    ));
    await tester.pumpAndSettle();
    explanations['Value'] = 'Caller mutation';
    expect(controller.columnHelp['Value'], help);
    expect(() => controller.columnHelp['Value'] = 'Mutation',
        throwsUnsupportedError);
    expect(info, findsOneWidget);
    final minimum = controller.columns.first.minWidth;
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.text(help), findsOneWidget);
    final newColumn = column('Value', width: 25);
    controller.columns = [newColumn];
    await controller.forceReload();
    await tester.pumpAndSettle();
    expect(find.text(help), findsNothing);
    expect(info, findsOneWidget);
    expect(newColumn.minWidth, minimum);
    expect(controller.stateManager.columns.first, newColumn);
    expect(controller.stateManager.rows, hasLength(1));
    // Rebuild the existing table without replacing its controller.
    final host = tester.state<_WrapperHostState>(find.byType(_WrapperHost));
    host.rebuild();
    await tester.pumpAndSettle();
    expect(info, findsOneWidget);
    expect(newColumn.minWidth, minimum);
    await tester.tap(info);
    await tester.pumpAndSettle();
    await closeGrid(tester);
    expect(find.text(help), findsNothing);
  });

  test('a competing renderer is rejected with the field in its diagnostic', () {
    final c = column('Value')..titleRenderer = (_) => const Text('Custom');
    expect(
      () => DataGridColumnHeader.install(
          [c], {'Value': help}, const TrinaGridStyleConfig()),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', contains('Value'))),
    );
  });
}

class _WrapperHost extends StatefulWidget {
  final SingleDataGridController<_MemoryRow> controller;
  const _WrapperHost({required this.controller});
  @override
  State<_WrapperHost> createState() => _WrapperHostState();
}

class _WrapperHostState extends State<_WrapperHost> {
  void rebuild() => setState(() {});
  @override
  Widget build(BuildContext context) => SingleTableDataGrid(widget.controller);
}

class _MemoryRow implements ITrinaRowModel {
  @override
  int get id => 1;
  @override
  TrinaRow toTrinaRow(BuildContext context) =>
      TrinaRow(cells: {'Value': TrinaCell(value: 'local')});
  @override
  Future<void> deleteMethod(BuildContext context) async {}
  @override
  Future<void> updateMethod(BuildContext context) async {}
  @override
  String toBasicString() => 'local';
}
