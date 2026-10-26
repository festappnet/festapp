import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

LayoutScenePainter scenePainter(WidgetTester tester, Finder surface) => tester
    .widgetList<CustomPaint>(
      find.descendant(of: surface, matching: find.byType(CustomPaint)),
    )
    .map((widget) => widget.painter)
    .whereType<LayoutScenePainter>()
    .single;

Future<void> pinchIn(WidgetTester tester, Offset center) async {
  final left = await tester.startGesture(
    center - const Offset(30, 0),
    pointer: 1,
    kind: PointerDeviceKind.touch,
  );
  final right = await tester.startGesture(
    center + const Offset(30, 0),
    pointer: 2,
    kind: PointerDeviceKind.touch,
  );
  for (var i = 1; i <= 6; i++) {
    await left.moveTo(center - Offset(30 + i * 15, 0));
    await right.moveTo(center + Offset(30 + i * 15, 0));
    await tester.pump();
  }
  await left.up();
  await right.up();
  await tester.pumpAndSettle();
}

Future<void> fingerDrag(WidgetTester tester, Offset from) async {
  final finger = await tester.startGesture(from, kind: PointerDeviceKind.touch);
  await finger.moveBy(const Offset(24, 0));
  await tester.pump();
  await finger.moveBy(const Offset(24, 12));
  await tester.pump();
  await finger.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'dark margin follows touch even when an ancestor owns the gesture arena',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      final document = VenueLayoutDocument.empty().copyWith(
        canvas: {'x': 0, 'y': 0, 'width': 800, 'height': 1000},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      EagerGestureRecognizer
                    >(() => EagerGestureRecognizer(), (_) {}),
              },
              child: LayoutSceneSurface(
                document: document,
                pan: true,
                onTap: (_) => taps++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byType(LayoutSceneSurface);
      final camera = scenePainter(tester, surface).camera!;
      for (final delta in [const Offset(-60, 0), const Offset(0, 60)]) {
        camera.value = Matrix4.diagonal3Values(3, 3, 1)
          ..setTranslationRaw(120, -180, 0);
        await tester.pump();
        final before = camera.value.clone();
        final finger = await tester.startGesture(
          const Offset(60, 300),
          kind: PointerDeviceKind.touch,
        );
        await finger.moveBy(delta / 2);
        await tester.pump();
        await finger.moveBy(delta / 2);
        await tester.pump();
        await finger.up();
        await tester.pumpAndSettle();
        expect(
          camera.value.entry(0, 3),
          closeTo(before.entry(0, 3) + delta.dx, .001),
        );
        expect(
          camera.value.entry(1, 3),
          closeTo(before.entry(1, 3) + delta.dy, .001),
        );
        expect(camera.value.entry(0, 0), 3);
      }
      expect(taps, 0);
    },
  );

  testWidgets(
    'margin pan applies once and hands pinch back to scale navigation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: VenueLayoutDocument.empty().copyWith(
                canvas: {'x': 0, 'y': 0, 'width': 800, 'height': 1000},
              ),
              pan: true,
              onTap: (_) => taps++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final camera = scenePainter(
        tester,
        find.byType(LayoutSceneSurface),
      ).camera!;
      camera.value = Matrix4.diagonal3Values(3, 3, 1)
        ..setTranslationRaw(120, -180, 0);
      await tester.pump();
      final first = await tester.startGesture(
        const Offset(60, 300),
        pointer: 1,
      );
      await first.moveBy(const Offset(-30, 0));
      await tester.pump();
      expect(
        camera.value.entry(0, 3),
        closeTo(90, .001),
        reason: 'Pointer and scale callbacks must not pan twice',
      );
      final second = await tester.startGesture(
        const Offset(120, 300),
        pointer: 2,
      );
      await second.moveBy(const Offset(30, 0));
      await tester.pump();
      await second.moveBy(const Offset(30, 0));
      await tester.pump();
      expect(camera.value.entry(0, 0), greaterThan(3));
      await first.cancel();
      await tester.pump();
      final before = camera.value.clone();
      await second.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(camera.value.entry(1, 3), greaterThan(before.entry(1, 3)));
      await second.up();
      await tester.pumpAndSettle();
      expect(taps, 0);
      camera.value = Matrix4.diagonal3Values(3, 3, 1)
        ..setTranslationRaw(120, -180, 0);
      await tester.pump();
      final next = await tester.startGesture(const Offset(60, 300));
      await next.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(camera.value.entry(1, 3), closeTo(-150, .001));
      await next.cancel();
      await tester.pumpAndSettle();
      expect(taps, 0);
    },
  );

  testWidgets('pinch and cancel never dispatch a selection tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutSceneSurface(
            document: VenueLayoutDocument.empty(),
            onTap: (_) => taps++,
          ),
        ),
      ),
    );
    final first = await tester.startGesture(
      const Offset(300, 300),
      pointer: 10,
    );
    final second = await tester.startGesture(
      const Offset(400, 300),
      pointer: 11,
    );
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
    final canceled = await tester.startGesture(const Offset(300, 300));
    await canceled.cancel();
    await tester.pumpAndSettle();
    expect(taps, 0);
    await tester.tapAt(const Offset(300, 300));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('mobile Select pans blank canvas and still drags objects', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 1200,
      y: 800,
      width: 200,
      height: 160,
      surface: const {'type': 'rect'},
    );
    final document = VenueLayoutDocument.empty().copyWith(nodes: [node]);
    final controller = VenueLayoutController(document);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: controller, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byWidgetPredicate(
      (widget) => widget is LayoutSceneSurface && widget.onDragStart != null,
    );
    final center = tester.getCenter(surface);
    final camera = scenePainter(tester, surface).camera!;
    await pinchIn(tester, center);
    expect(camera.value.entry(0, 0), greaterThan(1));
    expect(controller.document, document);
    final beforePan = camera.value.clone();
    await fingerDrag(tester, center + const Offset(-60, 130));
    expect(camera.value.entry(0, 3), greaterThan(beforePan.entry(0, 3)));
    expect(camera.value.entry(0, 0), beforePan.entry(0, 0));
    expect(controller.document, document);
    final painter = scenePainter(tester, surface);
    final objectCenter =
        tester.getTopLeft(surface) +
        MatrixUtils.transformPoint(
          camera.value,
          painter.offset + Offset(node.x, node.y) * painter.scale,
        );
    final beforeObject = camera.value.clone();
    await fingerDrag(tester, objectCenter);
    expect(controller.document.nodes.single.x, greaterThan(node.x));
    expect(camera.value, beforeObject);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile reservation surface pans by finger after pinch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutSceneSurface(
            document: VenueLayoutDocument.empty(),
            pan: true,
            compactZoomControls: true,
            onTap: (_) => taps++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byType(LayoutSceneSurface);
    final camera = scenePainter(tester, surface).camera!;
    final center = tester.getCenter(surface);
    await pinchIn(tester, center);
    expect(camera.value.entry(0, 0), greaterThan(1));
    final before = camera.value.clone();
    await fingerDrag(tester, center);
    expect(camera.value.entry(0, 3), greaterThan(before.entry(0, 3)));
    expect(camera.value.entry(0, 0), before.entry(0, 0));
    expect(taps, 0);
    expect(tester.takeException(), isNull);
  });
}
