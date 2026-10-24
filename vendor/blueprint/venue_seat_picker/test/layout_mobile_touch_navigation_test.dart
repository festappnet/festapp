import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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
