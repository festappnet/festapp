import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_table_selection.dart';

void main() {
  test(
    'only connected seats get short boundary links, including rotated and round tables',
    () {
      for (final shape in ['rect', 'circle']) {
        var doc = tableLayout(
          shape: shape,
          count: 6,
          x: 400,
          y: 400,
          width: 200,
          height: shape == 'circle' ? 200 : 120,
        );
        final table = doc.nodes.firstWhere((n) => n.kind == 'table');
        doc = doc.copyWith(
          nodes: [
            for (final n in doc.nodes)
              n.id == table.id ? n.copyWith(rotation: 37) : n,
            LayoutNode(id: newLayoutId(), kind: 'seat', x: 400, y: 200),
          ],
        );
        final before = doc.toJson(), links = tableSeatLinks(doc, {table.id});
        expect(links, hasLength(6));
        expect(
          links.map((l) => l.seatId).toSet(),
          doc.nodes
              .where((n) => n.parentId == table.id)
              .map((n) => n.id)
              .toSet(),
        );
        for (final link in links) {
          final p = transformPoint(
            inverseMatrix(worldMatrix(doc, doc.nodes.first)),
            link.tablePoint.dx,
            link.tablePoint.dy,
          );
          if (shape == 'rect') {
            expect(
              (p[0].abs() - 100).abs() < .001 || (p[1].abs() - 60).abs() < .001,
              isTrue,
            );
          } else {
            expect(Offset(p[0], p[1]).distance, closeTo(100, .2));
          }
          expect((link.seatPoint - link.tablePoint).distance, lessThan(45));
        }
        expect(tableSeatLinks(doc, {doc.nodes.last.id}), isEmpty);
        expect(tableSeatLinks(doc, {}), isEmpty);
        expect(doc.toJson(), before);
      }
    },
  );
  test(
    'selected manual chair shows its own attachment without sibling links',
    () {
      var doc = tableLayout(shape: 'rect', count: 6, x: 400, y: 400);
      final table = doc.nodes.firstWhere((n) => n.kind == 'table');
      final chair = doc.nodes.firstWhere((n) => n.kind == 'seat');
      doc = setTableSeatPlacement(doc, chair.id, {'mode': 'free'});
      doc = doc.copyWith(
        nodes: [
          for (final n in doc.nodes)
            n.id == chair.id ? n.copyWith(x: -350, y: 200) : n,
        ],
      );
      final before = doc.toJson();
      final links = tableSeatLinks(doc, {chair.id});
      expect(links.single.seatId, chair.id);
      expect(
        (links.single.tablePoint - links.single.seatPoint).distance,
        greaterThan(100),
      );
      expect(tableSeatLinks(doc, {table.id, chair.id}), hasLength(6));
      expect(doc.toJson(), before);
    },
  );
  testWidgets(
    'reservation selection highlights the tabletop instead of its chair assembly',
    (tester) async {
      final base = tableLayout(
        shape: 'rect',
        count: 6,
        x: 400,
        y: 300,
        width: 200,
        height: 120,
      );
      final table = base.nodes.firstWhere((node) => node.kind == 'table');
      final wrapper = LayoutNode(id: newLayoutId(), kind: 'group');
      final doc = base.copyWith(
        nodes: [
          wrapper,
          for (final node in base.nodes)
            node.id == table.id ? node.copyWith(parentId: wrapper.id) : node,
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 900,
            height: 700,
            child: LayoutSceneSurface(
              document: doc,
              selected: {wrapper.id},
              animate: false,
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<LayoutScenePainter>()
          .single;
      expect(painter.selected, {wrapper.id});
      expect(
        boundsOfPoints(painter.selectionHulls.single),
        boundsOfPoints(
          worldHull(
            doc.nodes.firstWhere((node) => node.id == table.id),
            worldMatrix(
              doc,
              doc.nodes.firstWhere((node) => node.id == table.id),
            ),
          ),
        ),
      );
      expect(painter.emphasizeSelection, isTrue);
      expect(find.byTooltip('Resize handle'), findsNothing);
    },
  );
  testWidgets(
    'linked chair highlights leave selection and all eight handles on the tabletop',
    (tester) async {
      final doc = tableLayout(
        shape: 'rect',
        count: 6,
        x: 400,
        y: 300,
        width: 200,
        height: 120,
      );
      final table = doc.nodes.firstWhere((n) => n.kind == 'table');
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 900,
            height: 700,
            child: LayoutSceneSurface(
              document: doc,
              selected: {table.id},
              onHandleStart: (_, _) {},
              animate: false,
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      expect(painter.selected, {table.id});
      expect(painter.seatLinks, hasLength(6));
      final bounds = boundsOfPoints(painter.selectionHulls.single);
      expect(bounds, {'x': 300.0, 'y': 240.0, 'width': 200.0, 'height': 120.0});
      for (final direction in [
        '',
        ' n',
        ' e',
        ' s',
        ' w',
        ' nw',
        ' ne',
        ' sw',
      ]) {
        expect(find.byTooltip('Resize$direction handle'), findsOneWidget);
      }
      expect(find.byTooltip('Rotate handle'), findsOneWidget);
    },
  );
  testWidgets(
    'native table wrapper uses tabletop handles and stable resize while moving its assembly',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = tableLayout(
        shape: 'roundedRect',
        count: 6,
        x: 400,
        y: 300,
        width: 200,
        height: 120,
      );
      final table = base.nodes.firstWhere((node) => node.kind == 'table');
      final wrapper = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 40,
        y: 60,
      );
      final original = base.copyWith(
        nodes: [
          wrapper,
          for (final node in base.nodes)
            node.id == table.id ? node.copyWith(parentId: wrapper.id) : node,
        ],
      );
      final controller = VenueLayoutController(original)..select({wrapper.id});
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: controller, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (widget) =>
              widget is LayoutSceneSurface && widget.onHandleStart != null,
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<LayoutScenePainter>()
          .firstWhere((painter) => painter.selected.contains(wrapper.id));
      final actualTable = original.nodes.firstWhere(
        (node) => node.id == table.id,
      );
      final matrix = worldMatrix(original, actualTable);
      final tabletop = boundsOfPoints(worldHull(actualTable, matrix));
      expect(painter.selected, {wrapper.id});
      expect(boundsOfPoints(painter.selectionHulls.single), tabletop);
      expect(painter.seatLinks, hasLength(6));
      for (final link in painter.seatLinks) {
        expect((link.seatPoint - link.tablePoint).distance, lessThan(45));
      }
      final paintOrigin = tester.getTopLeft(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && identical(widget.painter, painter),
        ),
      );
      for (final entry in <String, Offset>{
        'Resize e handle': Offset(table.width / 2, 0),
        'Resize w handle': Offset(-table.width / 2, 0),
        'Resize n handle': Offset(0, -table.height / 2),
        'Resize s handle': Offset(0, table.height / 2),
      }.entries) {
        final world = transformPoint(matrix, entry.value.dx, entry.value.dy);
        final screen =
            paintOrigin +
            MatrixUtils.transformPoint(
              painter.camera!.value,
              Offset(world[0], world[1]) * painter.scale + painter.offset,
            );
        expect(
          (tester.getCenter(find.byTooltip(entry.key)) - screen).distance,
          lessThan(.1),
        );
      }
      final center = Offset(matrix[4], matrix[5]);
      await tester.tap(find.widgetWithText(FilterChip, 'Snap'));
      await tester.pump();
      surface().onDragStart!(center);
      surface().onDragUpdate!(center + const Offset(24, 16));
      surface().onDragEnd!();
      expect(controller.selection, {wrapper.id});
      for (final node in base.nodes) {
        final before = worldMatrix(
          original,
          original.nodes.firstWhere((n) => n.id == node.id),
        );
        final after = worldMatrix(
          controller.document,
          controller.document.nodes.firstWhere((n) => n.id == node.id),
        );
        expect(after[4] - before[4], closeTo(24, .01));
        expect(after[5] - before[5], closeTo(16, .01));
      }
      controller.undo();
      await tester.pump();
      final east = Offset(
        tabletop['x']! + tabletop['width']!,
        tabletop['y']! + tabletop['height']! / 2,
      );
      surface().onHandleStart!('Resize e', east);
      surface().onDragUpdate!(east + const Offset(1, 0));
      await tester.pump();
      final resized = controller.document.nodes.firstWhere(
        (node) => node.id == table.id,
      );
      expect(resized.width, closeTo(table.width + 1, .01));
      expect(resized.height, table.height);
      final resizedBounds = boundsOfPoints(
        worldHull(resized, worldMatrix(controller.document, resized)),
      );
      expect(resizedBounds['x'], closeTo(tabletop['x']!, .01));
      surface().onDragEnd!();
      expect(controller.selection, {wrapper.id});
      for (final seat in base.nodes.where((node) => node.kind == 'seat')) {
        final after = controller.document.nodes.firstWhere(
          (node) => node.id == seat.id,
        );
        expect(after.width, seat.width);
        expect(after.height, seat.height);
      }
      controller.undo();
      expect(controller.document, same(original));
      expect(controller.canUndo, isFalse);
    },
  );

  test(
    'ordinary multi-object groups retain their complete selection bounds',
    () {
      final group = LayoutNode(id: newLayoutId(), kind: 'group');
      final document = VenueLayoutDocument(
        nodes: [
          group,
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            parentId: group.id,
            surface: const {'type': 'rect'},
          ),
          LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            parentId: group.id,
            x: 300,
          ),
        ],
      );
      expect(tabletopSelectionNode(document, group), same(group));
    },
  );
  testWidgets(
    'tables and bars have orthogonal edge controls without free vertex dragging',
    (tester) async {
      for (final bar in [false, true]) {
        final width = bar ? 180.0 : 200.0;
        final height = bar ? 120.0 : 200.0;
        final table = snapTableSurfaceToGrid(
          LayoutNode(
            id: newLayoutId(),
            kind: 'table',
            x: 400,
            y: 300,
            width: width,
            height: height,
            surface: const {'type': 'rect'},
            properties: {
              if (bar) 'furniture': 'bar',
              if (bar) 'guestSide': 'bottom',
            },
          ),
          preset: 'rectangle',
        );
        final document = VenueLayoutDocument(nodes: [table]);
        final before = document.toJson();
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 900,
              height: 700,
              child: LayoutSceneSurface(
                document: document,
                selected: {table.id},
                showSeatSelectionChecks: false,
                onHandleStart: (_, _) {},
                animate: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byTooltip('Resize handle'), findsOneWidget);
        expect(find.byTooltip('Resize e handle'), findsOneWidget);
        expect(find.byTooltip('Vertex 0 handle'), findsNothing);
        expect(find.byTooltip('Extend surface'), findsNWidgets(bar ? 10 : 8));
        expect(find.byTooltip('Rotate handle'), findsOneWidget);
        expect(document.toJson(), before);
      }
    },
  );
}
