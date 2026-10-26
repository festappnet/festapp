import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

Finder surfaceFinder() => find.byWidgetPredicate(
  (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
);
LayoutScenePainter painter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
      find.descendant(of: surfaceFinder(), matching: find.byType(CustomPaint)),
    )
    .map((w) => w.painter)
    .whereType<LayoutScenePainter>()
    .single;
Offset screen(WidgetTester tester, Offset world) {
  final p = painter(tester);
  return tester.getTopLeft(surfaceFinder()) +
      MatrixUtils.transformPoint(p.camera!.value, p.offset + world * p.scale);
}

Future<void> openEditor(WidgetTester tester, VenueLayoutController c) async {
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
  await tester.pumpAndSettle();
}

final tableId = newLayoutId();
VenueLayoutDocument document() => VenueLayoutDocument.empty().copyWith(
  canvas: {'x': 0, 'y': 0, 'width': 800, 'height': 200, 'fill': '#FFFFFFFF'},
  nodes: [
    LayoutNode(
      id: tableId,
      kind: 'table',
      surface: const {'type': 'rect'},
      x: 400,
      y: 100,
      width: 80,
      height: 60,
    ),
  ],
);
void main() {
  testWidgets(
    'Select touch pans blank margin and near miss; mouse keeps marquee',
    (tester) async {
      final doc = document();
      final c = VenueLayoutController(doc);
      await openEditor(tester, c);
      final p = painter(tester);
      p.camera!.value = Matrix4.diagonal3Values(2, 2, 1)
        ..setTranslationRaw(-250, -200, 0);
      await tester.pump();
      final start = tester.getTopLeft(surfaceFinder()) + const Offset(120, 25);
      final local = p.camera!.toScene(
        start - tester.getTopLeft(surfaceFinder()),
      );
      expect(
        (local - p.offset).dy / p.scale,
        lessThan(0),
        reason: 'Start is outside canvas',
      );
      c.select({tableId});
      await tester.pump();
      final before = p.camera!.value.clone();
      await tester.dragFrom(start, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(p.camera!.value, isNot(before));
      expect(c.selection, {tableId});
      expect(c.document.toJson(), doc.toJson());
      expect(c.canUndo, false);
      // The same near-miss point taps the table, but dragging pans.
      c.select({});
      await tester.pump();
      final zoom = painter(tester).scale * p.camera!.value.getMaxScaleOnAxis();
      final near = screen(tester, Offset(440 + 7 / zoom, 100));
      final panBefore = p.camera!.value.clone();
      await tester.dragFrom(near, const Offset(-50, 0));
      await tester.pumpAndSettle();
      expect(p.camera!.value, isNot(panBefore));
      expect(c.selection, isEmpty);
      expect(c.document.toJson(), doc.toJson());
      final mouse = await tester.startGesture(
        screen(tester, const Offset(330, 40)),
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveTo(screen(tester, const Offset(470, 150)));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(c.selection, {tableId});
      expect(c.canUndo, false);
    },
  );
  testWidgets(
    'editor completed near tap selects once including Shift and exact down',
    (tester) async {
      final c = VenueLayoutController(document());
      await openEditor(tester, c);
      for (final zoom in [.5, 1.0, 2.0]) {
        final p = painter(tester);
        final viewport = tester.getSize(surfaceFinder());
        p.camera!.value = Matrix4.diagonal3Values(zoom, zoom, 1)
          ..setTranslationRaw(
            (1 - zoom) * viewport.width / 2,
            (1 - zoom) * viewport.height / 2,
            0,
          );
        await tester.pump();
        final scale = p.scale * zoom;
        final at = screen(tester, Offset(440 + 7 / scale, 100));
        final finger = await tester.startGesture(at);
        expect(c.selection, isEmpty, reason: 'Slop must not select on down');
        await finger.up();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(c.selection, {tableId});
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final surface = tester.widget<LayoutSceneSurface>(surfaceFinder());
        final world = Offset(440 + 7 / scale, 100);
        surface.onSelectDown!(world);
        surface.onTap!(world);
        expect(c.selection, isEmpty, reason: 'Shift near tap toggles once');
        surface.onSelectDown!(world);
        surface.onTap!(world);
        expect(c.selection, {tableId});
        surface.onSelectDown!(const Offset(400, 100));
        surface.onTap!(const Offset(400, 100));
        expect(c.selection, isEmpty, reason: 'Shift direct tap toggles once');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      expect(c.canUndo, false);
    },
  );
  testWidgets('editor near taps cover six chairs, text and rendered line', (
    tester,
  ) async {
    final tableDoc = tableLayout(shape: 'rectangle', count: 6, x: 400, y: 300);
    final text = LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      properties: {'text': 'Caption'},
      x: 100,
      y: 100,
      width: 100,
      height: 40,
    );
    final line = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 300,
      y: 100,
      width: 100,
      properties: {'shape': 'line'},
      style: {'strokeWidth': 4},
    );
    final doc = tableDoc.copyWith(nodes: [...tableDoc.nodes, text, line]);
    final c = VenueLayoutController(doc);
    await openEditor(tester, c);
    final surface = tester.widget<LayoutSceneSurface>(surfaceFinder());
    final chair = doc.nodes.firstWhere((n) => n.kind == 'seat');
    final m = worldMatrix(doc, chair);
    for (final zoom in [.5, 1.0, 2.0]) {
      surface.onViewportScaleChanged!(zoom);
      final point = transformPoint(m, chair.width / 2 + 7 / zoom, 0);
      for (final (id, at) in [
        (chair.id, Offset(point[0], point[1])),
        (text.id, Offset(150 + 7 / zoom, 100)),
        (line.id, Offset(300, 102 + 7 / zoom)),
      ]) {
        c.select({});
        surface.onSelectDown!(at);
        expect(c.selection, isEmpty);
        surface.onTap!(at);
        expect(c.selection, {id});
      }
    }
    expect(c.document.toJson(), doc.toJson());
    expect(c.canUndo, false);
  });
  testWidgets(
    'picker nearest occupied target blocks a farther available seat',
    (tester) async {
      final free = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
      final occupied = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 150,
        y: 100,
      );
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: VenueLayoutDocument.empty().copyWith(
                nodes: [free, occupied],
              ),
              seatPresentation: {
                occupied.id: {'status': 'occupied'},
              },
              onSelectionRequested: (ids, selecting) async {
                calls++;
                return const LayoutSelectionResult(accepted: true);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.widget<LayoutSceneSurface>(surfaceFinder());
      surface.onViewportScaleChanged!(1);
      surface.onTap!(const Offset(127, 100));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        find.text('This seat or its paired seat is unavailable.'),
        findsOneWidget,
      );
      surface.onTap!(const Offset(100, 100));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );
  testWidgets('cancel restores object drag and touch navigation selection', (
    tester,
  ) async {
    final doc = document();
    final c = VenueLayoutController(doc);
    await openEditor(tester, c);
    c.select({tableId});
    await tester.pump();
    final finger = await tester.startGesture(
      screen(tester, const Offset(400, 100)),
    );
    await finger.moveBy(const Offset(45, 25));
    await finger.moveBy(const Offset(20, 10));
    await tester.pump();
    await finger.cancel();
    await tester.pumpAndSettle();
    expect(c.document.toJson(), doc.toJson());
    expect(c.canUndo, false);
    expect(c.selection, {tableId});
    final blank = await tester.startGesture(
      tester.getTopLeft(surfaceFinder()) + const Offset(120, 25),
    );
    await blank.moveBy(const Offset(-50, 0));
    await blank.cancel();
    await tester.pumpAndSettle();
    expect(c.selection, {tableId});
    expect(c.document.toJson(), doc.toJson());
    expect(c.gestureActive, false);
  });
  testWidgets(
    'object picker near tap reserves once and table has no reservation action',
    (tester) async {
      final doc = tableLayout(shape: 'rectangle', count: 6, x: 400, y: 300);
      final seat = doc.nodes.firstWhere((n) => n.kind == 'seat');
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutPicker(
              document: doc,
              onSelectionRequested: (ids, selecting) async {
                calls++;
                return const LayoutSelectionResult(accepted: true);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final m = worldMatrix(doc, seat);
      final p = painter(tester);
      final scale = p.scale * p.camera!.value.getMaxScaleOnAxis();
      // Offset toward the outside of the chair along its rotated local x axis.
      final local = Offset(seat.width / 2 + 7 / scale, 0);
      final world = transformPoint(m, local.dx, local.dy);
      await tester.tapAt(screen(tester, Offset(world[0], world[1])));
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tapAt(screen(tester, const Offset(400, 300)));
      await tester.pumpAndSettle();
      expect(calls, 1, reason: 'Table has no reservation action');
    },
  );
}
