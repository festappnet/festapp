import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/venue_layout_templates.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  for (final kind in ['text', 'shape', 'line']) {
    testWidgets(
      'decoration $kind receives clicks before canvas or background',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final node = kind == 'line'
            ? shapeFromPoints(
                'polyline',
                [
                  [200, 300],
                  [400, 300],
                ],
                properties: {'role': 'decoration'},
                style: {'stroke': '#000000FF', 'strokeWidth': 5},
              )
            : LayoutNode(
                id: newLayoutId(),
                kind: kind,
                x: 300,
                y: 300,
                width: 200,
                height: 80,
                label: kind == 'text' ? 'Pódium' : '',
                properties: {
                  'role': 'decoration',
                  if (kind == 'text') 'text': 'Pódium',
                  if (kind == 'shape') 'shape': 'rect',
                },
              );
        final c = VenueLayoutController(
          VenueLayoutDocument.empty().copyWith(nodes: [node]),
        );
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueLayoutEditor(controller: c, showGallery: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final surface = find.byType(LayoutSceneSurface);
        final painter = tester
            .widgetList<CustomPaint>(
              find.descendant(of: surface, matching: find.byType(CustomPaint)),
            )
            .map((w) => w.painter)
            .whereType<LayoutScenePainter>()
            .single;
        final point =
            tester.getTopLeft(surface) +
            MatrixUtils.transformPoint(
              painter.camera!.value,
              painter.offset +
                  Offset(kind == 'shape' ? 200 : 300, 300) * painter.scale,
            );
        await tester.tapAt(point);
        await tester.pumpAndSettle();
        expect(c.selection, {node.id});
        expect(
          tester.widget<LayoutSceneSurface>(surface).canvasSelected,
          isFalse,
        );
        expect(
          tester.widget<LayoutSceneSurface>(surface).backgroundSelected,
          isFalse,
        );
        expect(c.canUndo, isFalse);
      },
    );
  }
  testWidgets(
    'Scout architecture keeps empty-space gestures and precise object selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final doc = VenueLayoutTemplates.create('scout-ball-182');
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
      final finder = find.byType(LayoutSceneSurface);
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(finder);
      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(
            find.descendant(of: finder, matching: find.byType(CustomPaint)),
          )
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      Future<void> click(Offset world) async {
        c.select({});
        await tester.pump();
        final paint = painter();
        await tester.tapAt(
          tester.getTopLeft(finder) +
              MatrixUtils.transformPoint(
                paint.camera!.value,
                paint.offset + world * paint.scale,
              ),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
      }

      const blank = Offset(1600, 700);
      await click(blank);
      expect(
        c.selection,
        isEmpty,
        reason: 'Room fill must not capture empty space',
      );
      expect(surface().panOnTouchDown!(blank), isTrue);
      surface().onDoubleTapAt!(blank);
      await tester.pump();
      expect(surface().canvasSelected, isTrue);
      await click(blank);
      final stage = doc.nodes.firstWhere(
        (n) => n.kind == 'shape' && n.z == -30 && n.width > 1000,
      );
      await click(Offset(stage.x + stage.width / 2, stage.y));
      expect(c.selection, {stage.id});
      final label = doc.nodes.firstWhere(
        (n) => n.kind == 'text' && n.label == 'Pódium',
      );
      await click(Offset(label.x, label.y));
      expect(c.selection, {label.id});
      final table = doc.nodes.firstWhere(
        (n) => n.kind == 'table' && n.label == '1',
      );
      await click(Offset(table.x, table.y));
      expect(c.selection, {table.id});
      final room = doc.nodes.firstWhere((n) => n.kind == 'shape' && n.z == -40);
      final scale = painter().scale * painter().camera!.value.entry(0, 0);
      await click(Offset(room.x - room.width / 2 + 6 / scale, 500));
      expect(c.selection, {
        room.id,
      }, reason: 'Wall accepts an 8 screen pixel near-hit');
      c.select({});
      surface().onSelectDown!(const Offset(180, 690));
      surface().onDragStart!(const Offset(180, 690));
      surface().onDragUpdate!(const Offset(510, 810));
      surface().onDragEnd!();
      await tester.pump();
      expect(c.selection, contains(table.id));
      expect(c.selection, isNot(contains(room.id)));
      expect(c.document.toJson(), doc.toJson());
      expect(c.canUndo, isFalse);
    },
  );
}
