import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  test(
    'controller keeps explicit chair rotation through later moves and undo',
    () {
      final d = tableLayout(shape: 'circle', count: 4, width: 180, height: 180);
      final seat = d.nodes.firstWhere((node) => node.kind == 'seat');
      final c = VenueLayoutController(d);
      addTearDown(c.dispose);
      c.select({seat.id});
      c.rotateSelection(37);
      expect(c.error, isNull);
      final rotated = c.document.nodes.firstWhere((node) => node.id == seat.id);
      expect(seatRotationManual(c.document, rotated), true);
      c.moveSelection(60, 30);
      expect(c.error, isNull);
      final moved = c.document.nodes.firstWhere((node) => node.id == seat.id);
      expect(moved.rotation, rotated.rotation);
      expect(moved.x, isNot(rotated.x));
      c.undo();
      expect(
        c.document.nodes.firstWhere((node) => node.id == seat.id).rotation,
        rotated.rotation,
      );
      c.undo();
      expect(c.document.toJson(), d.toJson());
    },
  );
  Future<void> open(WidgetTester tester, VenueLayoutController c) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
  }

  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onTap != null,
        ),
      );

  testWidgets(
    'chair hit selects and moves only chair; table body moves assembly',
    (tester) async {
      final d = tableLayout(shape: 'rectangle', x: 400, y: 300);
      final table = d.nodes.firstWhere((n) => n.kind == 'table');
      final chair = d.nodes.firstWhere((n) => n.kind == 'seat');
      final c = VenueLayoutController(d);
      await open(tester, c);
      final matrix = worldMatrix(d, chair);
      final at = Offset(matrix[4], matrix[5]);
      surface(tester).onTap!(at);
      expect(c.selection, {chair.id});
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Resize handle'),
        findsOneWidget,
        reason: 'Editing a chair uses the normal geometry transform handles',
      );
      expect(find.byTooltip('Rotate handle'), findsOneWidget);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<LayoutScenePainter>()
          .firstWhere((painter) => painter.selected.contains(chair.id));
      expect(
        (painter.scene['items'] as List).any(
          (item) =>
              item['nodeId'] == chair.id &&
              item['kind'] == 'state' &&
              item['stroke'] == '#FFFFFFFF',
        ),
        isFalse,
        reason: 'Geometry selection must not render a commercial check marker',
      );
      expect(painter.selectionHulls, isNotEmpty);
      expect(surface(tester).showSeatSelectionChecks, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      surface(tester).onDragStart!(at);
      surface(tester).onDragUpdate!(at + const Offset(23, 11));
      surface(tester).onDragEnd!();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      final moved = c.document.nodes.firstWhere((n) => n.id == chair.id);
      expect(moved.x, isNot(chair.x));
      expect(c.document.nodes.firstWhere((n) => n.id == table.id).x, table.x);
      for (final other in d.nodes.where((n) => n.id != chair.id)) {
        final actual = c.document.nodes.firstWhere((n) => n.id == other.id);
        expect(actual.x, other.x);
        expect(actual.y, other.y);
      }
      c.undo();
      await tester.pump();
      surface(tester).onTap!(Offset(table.x, table.y));
      expect(c.selection, {table.id});
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      surface(tester).onDragStart!(Offset(table.x, table.y));
      surface(tester).onDragUpdate!(Offset(table.x + 23, table.y + 11));
      surface(tester).onDragEnd!();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      for (final original in d.nodes) {
        final actual = c.document.nodes.firstWhere((n) => n.id == original.id);
        final before = worldMatrix(d, original),
            after = worldMatrix(c.document, actual);
        expect(after[4] - before[4], closeTo(23, .01));
        expect(after[5] - before[5], closeTo(11, .01));
      }
    },
  );

  testWidgets(
    'native view and edit selection use bounds without commercial checks',
    (tester) async {
      final document = tableLayout(
        shape: 'round',
        width: 180,
        height: 180,
        count: 4,
      );
      final seat = document.nodes.firstWhere((node) => node.kind == 'seat');
      final controller = VenueLayoutController(document)..select({seat.id});
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      Future<void> render({required bool editing}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(
                controller: controller,
                showGallery: false,
                interactionEnabled: editing,
                viewSelection: {seat.id},
                onViewSelectionChanged: (_) {},
                seatPresentation: {
                  seat.id: {'selected': true},
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      bool hasCheck() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<LayoutScenePainter>()
          .where((painter) => painter.selected.contains(seat.id))
          .any(
            (painter) => (painter.scene['items'] as List).any(
              (item) =>
                  item['nodeId'] == seat.id &&
                  item['kind'] == 'state' &&
                  item['stroke'] == '#FFFFFFFF',
            ),
          );
      await render(editing: false);
      expect(surface(tester).showSeatSelectionChecks, isFalse);
      expect(hasCheck(), isFalse);
      expect(find.byTooltip('Resize handle'), findsNothing);
      await render(editing: true);
      expect(surface(tester).showSeatSelectionChecks, isFalse);
      expect(hasCheck(), isFalse);
      expect(find.byTooltip('Resize handle'), findsOneWidget);
      await render(editing: false);
      expect(hasCheck(), isFalse);
    },
  );

  testWidgets('couch seat hit preserves furniture assembly selection', (
    tester,
  ) async {
    final d = couchLayout();
    final couch = d.nodes.firstWhere((n) => n.kind == 'furniture');
    final chair = d.nodes.firstWhere(
      (n) => n.kind == 'seat' && n.parentId == couch.id,
    );
    final c = VenueLayoutController(d);
    await open(tester, c);
    final m = worldMatrix(d, chair);
    surface(tester).onTap!(Offset(m[4], m[5]));
    expect(c.selection, {couch.id});
  });
  testWidgets('canvas copy paste shortcuts defer to focused inline text', (
    tester,
  ) async {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      x: 300,
      y: 200,
      properties: {'text': 'Editable caption'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [node]),
    );
    String clipboard = '';
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
          return null;
        }
        if (call.method == 'Clipboard.getData') return {'text': clipboard};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(tester, c);
    surface(tester).onTap!(const Offset(300, 200));
    await tester.pump();
    Future<void> shortcut(LogicalKeyboardKey key, {bool meta = false}) async {
      final modifier = meta
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();
    }

    await shortcut(LogicalKeyboardKey.keyC);
    await shortcut(LogicalKeyboardKey.keyV, meta: true);
    expect(clipboard, contains('venue-layout-selection'));
    expect(c.document.nodes.length, 2);
    expect(c.document.nodes.map((n) => n.id).toSet().length, 2);
    c.select({node.id});
    surface(tester).onTap!(const Offset(300, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(const ValueKey('layout-inline-label')), findsOneWidget);
    await shortcut(LogicalKeyboardKey.keyC);
    await shortcut(LogicalKeyboardKey.keyV, meta: true);
    expect(c.document.nodes.length, 2);
  });
}
