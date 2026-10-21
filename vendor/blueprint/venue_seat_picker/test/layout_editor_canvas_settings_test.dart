import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'rapid canvas input publishes one preview per frame and flushes the final pointer on release',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = tableLayout(shape: 'rect', count: 8);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-canvas')));
      await tester.pumpAndSettle();
      LayoutSceneSurface surface() =>
          tester.widget(find.byType(LayoutSceneSurface));
      var updates = 0;
      c.addListener(() => updates++);
      final right =
          (original.canvas['x'] as num) + (original.canvas['width'] as num);
      surface().onHandleStart!(
        'Canvas resize e',
        Offset(right.toDouble(), 300),
      );
      for (var i = 1; i <= 100; i++) {
        surface().onDragUpdate!(Offset(right + i.toDouble(), 300));
      }
      expect(
        updates,
        lessThanOrEqualTo(1),
        reason:
            'Intermediate pointer positions cannot be painted in the same frame',
      );
      await tester.pump();
      expect(
        c.document.canvas['width'],
        (original.canvas['width'] as num) + 100,
      );
      surface().onDragUpdate!(Offset(right + 130, 300));
      surface().onDragEnd!();
      expect(
        c.document.canvas['width'],
        (original.canvas['width'] as num) + 130,
      );
      await tester.pump();
      c.undo();
      expect(c.document, same(original));
      expect(c.canUndo, isFalse);
      surface().onHandleStart!(
        'Canvas resize e',
        Offset(right.toDouble(), 300),
      );
      surface().onDragUpdate!(Offset(right + 500, 300));
      surface().onDragCancel!();
      await tester.pump();
      expect(c.document, same(original));
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'canvas drag retains the inspector across host rebuilds and changes only canvas bounds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = tableLayout(shape: 'rect', count: 8);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: c,
              builder: (_, _) =>
                  VenueLayoutEditor(controller: c, showGallery: false),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-canvas')));
      await tester.pumpAndSettle();
      final inspector = tester.widget<LayoutInspector>(
        find.byType(LayoutInspector),
      );
      LayoutSceneSurface surface() =>
          tester.widget(find.byType(LayoutSceneSurface));
      final right =
          (original.canvas['x'] as num) + (original.canvas['width'] as num);
      surface().onHandleStart!(
        'Canvas resize e',
        Offset(right.toDouble(), 300),
      );
      for (var step = 1; step <= 5; step++) {
        surface().onDragUpdate!(Offset(right + step * 20.0, 300));
        await tester.pump();
        expect(
          tester.widget<LayoutInspector>(find.byType(LayoutInspector)),
          same(inspector),
          reason:
              'A host rebuild must not invalidate unchanged panels on every pointer event',
        );
        for (var i = 0; i < original.nodes.length; i++) {
          expect(c.document.nodes[i], same(original.nodes[i]));
        }
      }
      surface().onDragEnd!();
      await tester.pump();
      expect(
        c.document.canvas['width'],
        (original.canvas['width'] as num) + 100,
      );
      c.undo();
      expect(c.document, same(original));
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'canvas settings expand a canvas covered by a full-size rectangle',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final floor = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        properties: {'shape': 'rectangle'},
        x: 200,
        y: 200,
        width: 400,
        height: 400,
      );
      final controller = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': 400,
            'height': 400,
            'fill': '#FFFFFFFF',
          },
          nodes: [floor],
        ),
      );
      addTearDown(controller.dispose);
      controller.select({floor.id});
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.purple,
            ).copyWith(surface: Colors.purple.shade50),
          ),
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: controller,
              showGallery: false,
              toolbarTrailing: const Text('Host save'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-canvas')));
      await tester.pumpAndSettle();
      expect(controller.selection, isEmpty);
      expect(
        tester
            .widget<LayoutInspector>(find.byType(LayoutInspector))
            .canvasSelected,
        isTrue,
      );
      final width = find.descendant(
        of: find.byKey(const ValueKey('Width')),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(width);
      await tester.enterText(width, '600');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(controller.document.canvas['width'], 600);
      expect(controller.document.nodes.single.toJson(), floor.toJson());
      controller.updateNode(floor.copyWith(x: 220));
      expect(controller.document.nodes.single.x, 220);
      controller.undo();
      controller.undo();
      await tester.pumpAndSettle();
      expect(controller.document.canvas['width'], 400);
      final inspector = tester.getRect(find.byType(LayoutInspector));
      expect(
        tester
            .widget<Material>(find.byKey(const ValueKey('layout-palette')))
            .color,
        Colors.white,
      );
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(
                    of: find.byType(LayoutInspector),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .color,
        Colors.white,
      );
      expect(
        inspector.top,
        greaterThanOrEqualTo(tester.getTopLeft(find.byType(LayoutSceneSurface).first).dy),
      );
      expect(inspector.height, greaterThan(750));
      expect(tester.takeException(), isNull);
    },
  );
}
