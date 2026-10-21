import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'wheel and pinch stop at canvas fit and pan cannot lose the plan',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: VenueLayoutDocument.empty(),
              pan: true,
            ),
          ),
        ),
      );
      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      final camera = painter().camera!;
      for (var i = 0; i < 8; i++) {
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(400, 300),
            scrollDelta: Offset(0, 1000),
          ),
        );
      }
      expect(camera.value.entry(0, 0), closeTo(.9, .000001));
      final trackpad = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await trackpad.panZoomStart(const Offset(400, 300));
      await trackpad.panZoomUpdate(const Offset(400, 300), scale: .001);
      await trackpad.panZoomEnd();
      expect(camera.value.entry(0, 0), closeTo(.9, .000001));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(400, 300),
          scrollDelta: Offset(0, 100000),
        ),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final origin = MatrixUtils.transformPoint(camera.value, painter().offset);
      final end = MatrixUtils.transformPoint(
        camera.value,
        painter().offset + Offset(2400, 1600) * painter().scale,
      );
      expect(origin.dx, greaterThanOrEqualTo(15.99));
      expect(end.dx, lessThanOrEqualTo(784.01));
      expect(origin.dy, greaterThanOrEqualTo(15.99));
      expect(end.dy, lessThanOrEqualTo(584.01));
      final worldZoom = painter().scale * camera.value.entry(0, 0);
      await tester.binding.setSurfaceSize(const Size(360, 700));
      await tester.pump();
      expect(
        painter().scale * camera.value.entry(0, 0),
        closeTo(worldZoom, .000001),
        reason: 'Viewport changes preserve zoom; Fit plan explicitly resets it',
      );
      await tester.tap(find.byTooltip('Fit plan'));
      await tester.pump();
      expect(camera.value, Matrix4.identity());
    },
  );

  testWidgets(
    'selected-object canvas zooms wheel at pointer and Shift-wheel pans without edits',
    (tester) async {
      var edits = 0;
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 300,
        y: 200,
        surface: const {'type': 'rect'},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: VenueLayoutDocument.empty().copyWith(nodes: [node]),
              selected: {node.id},
              pan: false,
              showControls: false,
              onDragStart: (_) => edits++,
              onDragUpdate: (_) => edits++,
              onDragEnd: () => edits++,
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      final camera = painter.camera!;
      const point = Offset(310, 220);
      final anchor = camera.toScene(point);
      await tester.sendEventToBinding(
        const PointerScrollEvent(position: point, scrollDelta: Offset(0, -80)),
      );
      expect(camera.value.getMaxScaleOnAxis(), greaterThan(1));
      expect((camera.toScene(point) - anchor).distance, lessThan(.001));
      final zoom = camera.value.getMaxScaleOnAxis();
      final before = camera.value.entry(0, 3);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendEventToBinding(
        const PointerScrollEvent(position: point, scrollDelta: Offset(0, 70)),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(camera.value.getMaxScaleOnAxis(), zoom);
      expect(camera.value.entry(0, 3), closeTo(before - 70, .001));
      expect(edits, 0);
    },
  );

  testWidgets(
    'trackpad pan pinch works while mouse drag remains an object edit',
    (tester) async {
      var starts = 0, updates = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: VenueLayoutDocument.empty(),
              pan: false,
              showControls: false,
              onDragStart: (_) => starts++,
              onDragUpdate: (_) => updates++,
            ),
          ),
        ),
      );
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      final camera = painter.camera!;
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      const point = Offset(300, 200);
      await gesture.panZoomStart(point);
      await gesture.panZoomUpdate(point, pan: const Offset(30, 20));
      await gesture.panZoomUpdate(point, pan: const Offset(60, 40), scale: 1.5);
      await gesture.panZoomEnd();
      await tester.pump();
      expect(camera.value.getMaxScaleOnAxis(), greaterThan(1));
      expect(camera.value.entry(0, 3), isNot(0));
      expect(starts, 0);
      expect(updates, 0);
      final before = camera.value.clone();
      final mouse = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
      );
      await mouse.moveBy(const Offset(40, 20));
      await mouse.moveBy(const Offset(20, 10));
      await mouse.up();
      expect(starts, 1);
      expect(updates, greaterThan(0));
      expect(camera.value, before);
    },
  );
  testWidgets(
    'selection responds on pointer down without waiting for double tap',
    (tester) async {
      var selections = 0, taps = 0, doubleTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: VenueLayoutDocument.empty(),
              pan: false,
              showControls: false,
              onSelectDown: (_) => selections++,
              onTap: (_) => taps++,
              onDoubleTapAt: (_) => doubleTaps++,
            ),
          ),
        ),
      );
      final click = await tester.startGesture(const Offset(300, 200));
      expect(selections, 1); // No frame or double-tap timeout has elapsed.
      expect(taps, 0);
      await click.up();
      await tester.pump(const Duration(milliseconds: 50));
      final second = await tester.startGesture(const Offset(300, 200));
      expect(selections, 2);
      await second.up();
      expect(doubleTaps, 1);
      expect(taps, 0);
      await tester.pump(const Duration(milliseconds: 300));
    },
  );

  testWidgets(
    'row resize handles enclose all chairs and do not select canvas on down',
    (tester) async {
      final d = rowLayout(x: 300, y: 200);
      final root = d.nodes.firstWhere((n) => n.kind == 'group');
      var selections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: d,
              selected: {root.id},
              pan: false,
              showControls: false,
              onSelectDown: (_) => selections++,
              onHandleStart: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.byTooltip('Resize handle'), findsOneWidget);
      expect(find.byTooltip('Resize nw handle'), findsOneWidget);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      final bounds = selectionBounds(d, {root.id});
      final expected =
          Offset(
                bounds['x']! + bounds['width']!,
                bounds['y']! + bounds['height']!,
              ) *
              painter.scale +
          painter.offset;
      expect(
        (tester.getCenter(find.byTooltip('Resize handle')) - expected).distance,
        lessThan(.01),
      );
      final click = await tester.startGesture(
        tester.getCenter(find.byTooltip('Resize handle')),
      );
      expect(selections, 0);
      await click.up();
    },
  );
}
