import 'dart:ui' show SemanticsAction;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'imported table group selects at the tabletop and has handles around its contents',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.binding.setSurfaceSize(const Size(1440, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final group = newLayoutId(),
            table = newLayoutId(),
            chair = newLayoutId();
        final doc = VenueLayoutDocument(
          nodes: [
            LayoutNode(
              id: group,
              kind: 'group',
              label: 'Table group',
              width: 1,
              height: 1,
            ),
            LayoutNode(
              id: table,
              parentId: group,
              kind: 'table',
              x: 1000,
              y: 700,
              width: 180,
              height: 100,
              surface: const {'type': 'rect'},
            ),
            LayoutNode(
              id: chair,
              parentId: table,
              kind: 'seat',
              x: 0,
              y: -110,
              width: 40,
              height: 40,
            ),
          ],
        );
        final c = VenueLayoutController(doc);
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(controller: c, showGallery: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final canvas = tester.getSemantics(
          find.bySemanticsLabel(RegExp(r'^Layout canvas\. Select an object')),
        );
        expect(
          canvas.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason:
              'A secondary-click recognizer must not consume primary canvas clicks as semantic taps',
        );
        final f = find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onTap != null,
        );
        final r = tester.getRect(f),
            scale = math.min((r.width - 32) / 2400, (r.height - 32) / 1600);
        final origin =
            r.topLeft +
            Offset((r.width - 2400 * scale) / 2, (r.height - 1600 * scale) / 2);
        await tester.tapAt(origin + Offset(1000 * scale, 700 * scale));
        await tester.pumpAndSettle();
        expect(c.selection, {group});
        final bounds = selectionBounds(c.document, {group});
        final expected =
            origin +
            Offset(
              (bounds['x']! + bounds['width']!) * scale,
              (bounds['y']! + bounds['height']!) * scale,
            );
        final resizeHandle = find.byTooltip('Resize handle');
        final actual = tester.getCenter(resizeHandle);
        expect(
          (actual - expected).distance,
          lessThan(1),
          reason: 'The wrapper uses the physical tabletop edit bounds',
        );
        final before = c.document;
        final gesture = await tester.startGesture(actual);
        await gesture.moveBy(const Offset(25, 25));
        await gesture.moveBy(const Offset(40, 30));
        await tester.pump();
        expect(c.error, isNull);
        expect(
          c.document.nodes.firstWhere((n) => n.id == table).width,
          greaterThan(180),
          reason: 'Resize must affect visible geometry',
        );
        expect(
          c.document.nodes.map((n) => n.id).toSet(),
          before.nodes.map((n) => n.id).toSet(),
        );
        expect(
          c.document.nodes.firstWhere((n) => n.id == chair).parentId,
          table,
        );
        await gesture.up();
        await tester.pumpAndSettle();
        final resized = c.document;
        final tabletop = resized.nodes.firstWhere((n) => n.id == table);
        final groupNode = resized.nodes.firstWhere((n) => n.id == group);
        final center =
            origin +
            Offset(
              (groupNode.x + tabletop.x) * scale,
              (groupNode.y + tabletop.y) * scale,
            );
        final move = await tester.startGesture(center);
        await move.moveBy(const Offset(25, 25));
        await move.moveBy(const Offset(35, 20));
        await tester.pump();
        expect(
          c.document.nodes.firstWhere((n) => n.id == group).x,
          greaterThan(groupNode.x),
          reason: 'Dragging updates before mouse-up',
        );
        await move.up();
        await tester.pumpAndSettle();
        expect(c.error, isNull);
        final seat = c.document.nodes.firstWhere((node) => node.id == chair);
        final seatPosition = worldMatrix(c.document, seat);
        expect(hitTest(c.document, seatPosition[4], seatPosition[5]), chair);
        final seatScreen =
            origin + Offset(seatPosition[4] * scale, seatPosition[5] * scale);
        for (final element
            in find
                .byWidgetPredicate(
                  (widget) =>
                      widget is Tooltip &&
                      widget.message?.startsWith('Resize') == true,
                )
                .evaluate()) {
          expect(
            tester.getRect(find.byWidget(element.widget)).contains(seatScreen),
            isFalse,
          );
        }

        await tester.tapAt(
          origin + Offset(seatPosition[4] * scale, seatPosition[5] * scale),
        );
        await tester.pumpAndSettle();
        expect(
          c.selection,
          {chair},
          reason:
              'A commercial table group keeps each imported chair individually selectable',
        );
        expect(find.byTooltip('Resize handle'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets('fit-view table body stays draggable between resize targets', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = VenueLayoutController(
      VenueLayoutDocument(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 1920,
          'height': 3456,
          'fill': '#FFFFFFFF',
        },
      ),
    );
    addTearDown(c.dispose);
    c.insert(tableLayout(shape: 'roundedRect', x: 960, y: 1600));
    final id = c.selection.single;
    final before = c.document.nodes.firstWhere((n) => n.id == id);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 848,
            child: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate(
      (w) => w is LayoutSceneSurface && w.onTap != null,
    );
    final rect = tester.getRect(surface);
    final scale = math.min((rect.width - 32) / 1920, (rect.height - 32) / 3456);
    final origin =
        rect.topLeft +
        Offset(
          (rect.width - 1920 * scale) / 2,
          (rect.height - 3456 * scale) / 2,
        );
    final pointer = await tester.startGesture(
      origin + Offset(before.x * scale, before.y * scale),
    );
    await pointer.moveBy(const Offset(30, 0));
    await pointer.moveBy(const Offset(60, 0));
    await tester.pump();
    final during = c.document.nodes.firstWhere((n) => n.id == id);
    expect(
      during.x,
      greaterThan(before.x),
      reason: 'The table body must move before mouse-up',
    );
    expect(during.width, before.width);
    expect(during.height, before.height);
    await pointer.up();
    await tester.pumpAndSettle();
    expect(c.error, isNull);
  });
}
