import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  Future<void> open(WidgetTester tester, VenueLayoutController c) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
        ),
      );

  testWidgets(
    'palette chair drops into table assembly in one undo transaction',
    (tester) async {
      final original = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(original);
      await open(tester, c);
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final point = Offset(table.x, table.y);
      surface(tester).onDropPreview!('Seat', point);
      await tester.pump();
      expect(surface(tester).highlightedIds, {table.id});
      final addedId = c.document.nodes
          .firstWhere((n) => !original.nodes.any((old) => old.id == n.id))
          .id;
      surface(tester).onDrop!('Seat', point);
      await tester.pumpAndSettle();
      expect(
        c.document.nodes.where((n) => n.parentId == table.id),
        hasLength(7),
      );
      expect(
        c.document.nodes.firstWhere((n) => n.id == addedId).parentId,
        table.id,
      );
      expect(
        c.document.attachments.any(
          (a) => a['seatId'] == addedId && a['targetId'] == table.id,
        ),
        true,
      );
      expect(
        seatPlacementFree(
          c.document,
          c.document.nodes.firstWhere((n) => n.id == addedId),
        ),
        false,
      );
      final items = compileScene(c.document)['items'] as List;
      final oldSeat = original.nodes.firstWhere((n) => n.kind == 'seat');
      final newBody = items.firstWhere(
        (i) => i['id'] == addedId && i['kind'] == 'seat',
      );
      final oldBody = items.firstWhere(
        (i) => i['id'] == oldSeat.id && i['kind'] == 'seat',
      );
      expect(newBody['fill'], oldBody['fill']);
      expect(
        c.document.nodes.firstWhere((n) => n.id == addedId).width,
        oldSeat.width,
      );
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
    },
  );

  testWidgets(
    'existing standalone chair can attach, full table rejects provisional copy',
    (tester) async {
      final tableDoc = tableLayout(shape: 'roundedRect', count: 6);
      final chair = LayoutNode(id: newLayoutId(), kind: 'seat', x: 800, y: 500);
      final original = tableDoc.copyWith(nodes: [...tableDoc.nodes, chair]);
      final c = VenueLayoutController(original);
      await open(tester, c);
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      surface(tester).onDragStart!(Offset(chair.x, chair.y));
      surface(tester).onDragUpdate!(Offset(table.x, table.y));
      surface(tester).onDragEnd!();
      expect(
        c.document.nodes.firstWhere((n) => n.id == chair.id).parentId,
        table.id,
      );
      expect(
        seatPlacementFree(
          c.document,
          c.document.nodes.firstWhere((n) => n.id == chair.id),
        ),
        false,
      );
      c.undo();
      expect(c.document.toJson(), original.toJson());
      final full = reflowTable(original, table.id, tableCapacity(table));
      c.apply(full);
      c.markSaved();
      surface(tester).onDrop!('Seat', Offset(table.x, table.y));
      expect(c.document.toJson(), full.toJson());
      expect(c.error, contains('no free chair positions'));
      expect(c.canUndo, false);
    },
  );

  testWidgets(
    'placing a line returns to selection instead of inserting more lines',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == 'Line',
      );
      await tester.enterText(find.byType(TextField).first, 'Line');
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      surface(tester).onPointTap!(const Offset(400, 300));
      await tester.pump();
      surface(tester).onPointTap!(const Offset(560, 300));
      await tester.pumpAndSettle();
      expect(c.document.nodes, hasLength(1));
      surface(tester).onTap!(const Offset(420, 304));
      await tester.pumpAndSettle();
      expect(c.document.nodes, hasLength(1));
      expect(c.selection, {c.document.nodes.single.id});
    },
  );

  testWidgets(
    'thin line is selectable beside stroke and its endpoints can be edited',
    (tester) async {
      final line = shapeFromPoints(
        'line',
        [
          [300, 300],
          [600, 300],
        ],
        style: {'stroke': '#334155FF', 'strokeWidth': 1},
      );
      final original = VenueLayoutDocument.empty().copyWith(nodes: [line]);
      final c = VenueLayoutController(original);
      await open(tester, c);
      surface(tester).onTap!(const Offset(450, 307));
      await tester.pumpAndSettle();
      expect(c.selection, {line.id});
      expect(find.byTooltip('Vertex 0 handle'), findsOneWidget);
      expect(find.byTooltip('Vertex 1 handle'), findsOneWidget);
      expect(find.byTooltip('Resize handle'), findsNothing);
      surface(tester).onHandleStart!('Vertex 1', const Offset(600, 300));
      surface(tester).onDragUpdate!(const Offset(650, 350));
      surface(tester).onDragEnd!();
      expect(c.document.nodes.single.width, 350);
      expect(c.document.nodes.single.height, 50);
      final points = c.document.nodes.single.properties['points'] as List;
      final matrix = worldMatrix(c.document, c.document.nodes.single);
      expect(
        transformPoint(
          matrix,
          (points.first as List)[0],
          (points.first as List)[1],
        ),
        [300, 300],
      );
      c.undo();
      expect(c.document.toJson(), original.toJson());
    },
  );
}
