import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('mobile reservations retain one-finger pan after pinch zoom',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = VenueLayoutController(VenueLayoutDocument.empty());
    final originalDocument = controller.document;
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VenueLayoutEditor(
          controller: controller,
          interactionEnabled: false,
          showGallery: false,
          viewSelection: const {},
          onViewSelectionChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final surface = find.byType(LayoutSceneSurface).first;
    final center = tester.getCenter(surface);
    final painter = tester
        .widgetList<CustomPaint>(
            find.descendant(of: surface, matching: find.byType(CustomPaint)))
        .map((w) => w.painter)
        .whereType<LayoutScenePainter>()
        .single;
    final camera = painter.camera!;
    final initialZoom = camera.value.entry(0, 0);
    final first =
        await tester.startGesture(center - const Offset(35, 0), pointer: 1);
    final second =
        await tester.startGesture(center + const Offset(35, 0), pointer: 2);
    for (var i = 0; i < 4; i++) {
      await first.moveBy(const Offset(-15, 0));
      await second.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(camera.value.entry(0, 0), greaterThan(initialZoom));
    final zoom = camera.value.entry(0, 0);
    final before = camera.value.entry(0, 3);
    await tester.dragFrom(center, const Offset(-60, 0));
    await tester.pumpAndSettle();
    final afterLeft = camera.value.entry(0, 3);
    expect(afterLeft, lessThan(before - 20));
    await tester.dragFrom(center, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(camera.value.entry(0, 3), greaterThan(afterLeft + 20));
    expect(camera.value.entry(0, 0), closeTo(zoom, .000001));
    expect(controller.document, same(originalDocument));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
