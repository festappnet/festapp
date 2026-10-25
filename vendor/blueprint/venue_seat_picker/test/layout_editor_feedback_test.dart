import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_palette_drag_feedback.dart';

void main() {
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

  testWidgets('palette drag shows only a centered transparent object preview', (
    tester,
  ) async {
    final c = VenueLayoutController(VenueLayoutDocument.empty());
    await open(tester, c);
    final tile = find.byWidgetPredicate(
      (w) => w is Draggable<String> && w.data == 'Seat',
    );
    final start = tester.getCenter(tile);
    final gesture = await tester.startGesture(start);
    final pointer = start + const Offset(45, 20);
    await gesture.moveTo(pointer);
    await tester.pump();
    final feedback = find.byKey(const ValueKey('palette-drag-feedback'));
    expect(feedback, findsOneWidget);
    expect((tester.getCenter(feedback) - pointer).distance, lessThan(.01));
    expect(
      find.descendant(of: feedback, matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(of: feedback, matching: find.byType(Material)),
      findsNothing,
    );
    final preview =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: feedback,
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as LayoutScenePainter;
    expect((preview.scene['canvas'] as Map)['fill'], '#00000000');
    expect((preview.scene['items'] as List).single['kind'], 'seat');
    expect(tester.getSize(feedback).width, closeTo(40 * preview.scale, .001));
    await gesture.cancel();
    await tester.pump();
  });

  testWidgets(
    'palette overlay disappears when the canvas owns the insertion preview',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == 'Table',
      );
      final start = tester.getCenter(tile);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(45, 20));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('palette-drag-feedback')),
        findsOneWidget,
      );
      final surface = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDrop != null,
      );
      await gesture.moveTo(tester.getCenter(surface));
      await tester.pump();
      await gesture.moveBy(const Offset(12, 8));
      await tester.pump();
      expect(c.document.nodes.where((n) => n.kind == 'table'), hasLength(1));
      expect(find.byKey(const ValueKey('palette-drag-feedback')), findsNothing);
      await gesture.cancel();
      await tester.pump();
      expect(c.document.nodes, isEmpty);
    },
  );

  testWidgets(
    'blocked palette drop stays visible with a prohibition badge and recovers to one canvas preview',
    (tester) async {
      final source = tableLayout(shape: 'rect', count: 0, x: 1200, y: 800);
      final c = VenueLayoutController(source);
      await open(tester, c);
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == 'Table',
      );
      final start = tester.getCenter(tile);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + const Offset(45, 20));
      await tester.pump();
      final surface = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDrop != null,
      );
      final blocked = tester.getCenter(surface);
      await gesture.moveTo(blocked);
      await tester.pump();
      await gesture.moveBy(const Offset(1, 0));
      await tester.pump();
      expect(c.document.toJson(), source.toJson());
      expect(
        find.byKey(const ValueKey('palette-drag-feedback')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('palette-drop-blocked')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.text('Cannot place here'), findsOneWidget);
      await gesture.moveTo(blocked + const Offset(170, 0));
      await tester.pump();
      expect(c.document.nodes.where((n) => n.kind == 'table'), hasLength(2));
      expect(find.byKey(const ValueKey('palette-drag-feedback')), findsNothing);
      expect(find.byKey(const ValueKey('palette-drop-blocked')), findsNothing);
      await gesture.cancel();
      await tester.pump();
      expect(c.document.toJson(), source.toJson());
    },
  );

  testWidgets('error notice overlays canvas without moving its viewport', (
    tester,
  ) async {
    final c = VenueLayoutController(tableLayout(shape: 'rect', count: 0));
    await open(tester, c);
    final surface = find.byWidgetPredicate(
      (w) => w is LayoutSceneSurface && w.onTap != null,
    );
    final before = tester.getRect(surface);
    c.error = 'Cannot shrink this object.';
    c.select({c.document.nodes.first.id});
    await tester.pump();
    expect(find.byKey(const ValueKey('canvas-notice')), findsOneWidget);
    expect(tester.getRect(surface), before);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(c.error, isNull);
    expect(find.byKey(const ValueKey('canvas-notice')), findsNothing);
    expect(tester.getRect(surface), before);
  });
  testWidgets(
    'asymmetric rotated feedback preserves origin and follows canvas zoom',
    (tester) async {
      final base = rowLayout(x: 0, y: 0);
      final root = base.nodes.firstWhere((n) => n.parentId == null);
      final document = base.copyWith(
        nodes: base.nodes
            .map((n) => n.id == root.id ? n.copyWith(rotation: 27) : n)
            .toList(),
      );
      final changes = ValueNotifier(0);
      addTearDown(changes.dispose);
      var zoom = .4;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 200,
                  top: 200,
                  child: LayoutPaletteDragFeedback(
                    document: () => document,
                    scale: () => zoom,
                    changes: changes,
                    resources: const {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final feedback = find.byKey(const ValueKey('palette-drag-feedback'));
      final bounds = selectionBounds(document, {root.id});
      void check() {
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: feedback,
                        matching: find.byType(CustomPaint),
                      ),
                    )
                    .painter!
                as LayoutScenePainter;
        expect(
          tester.getSize(feedback).width,
          closeTo(bounds['width']! * zoom, .001),
        );
        expect(
          tester.getSize(feedback).height,
          closeTo(bounds['height']! * zoom, .001),
        );
        expect(
          (tester.getTopLeft(feedback) +
                  painter.offset -
                  const Offset(200, 200))
              .distance,
          lessThan(.001),
        );
        expect(painter.scale, zoom);
      }

      check();
      zoom = .8;
      changes.value++;
      await tester.pump();
      check();
    },
  );
  testWidgets(
    'palette feedback survives crossing gray viewport before first frame',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      final tile = find.byWidgetPredicate(
        (w) => w is Draggable<String> && w.data == 'Seat',
      );
      final main = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onDrop != null,
      );
      final gesture = await tester.startGesture(tester.getCenter(tile));
      await gesture.moveTo(tester.getTopLeft(main) + const Offset(2, 100));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.document.nodes, isEmpty);
      final feedback = tester.widget<LayoutPaletteDragFeedback>(
        find.byType(LayoutPaletteDragFeedback),
      );
      final id = feedback.document().nodes.single.id;
      await gesture.moveTo(tester.getCenter(main));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(c.document.nodes.single.id, id);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.document.nodes.single.id, id);
      c.undo();
      expect(c.document.nodes, isEmpty);
    },
  );
}
