import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('zero stroke means no outline, matching the SVG renderer', (
    tester,
  ) async {
    for (final width in [0.0, 2.0]) {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 50,
        y: 50,
        width: 60,
        height: 60,
        properties: {},
        style: {
          'fill': '#FFFFFFFF',
          'stroke': '#0000FFFF',
          'strokeWidth': width,
        },
      );
      final scene = compileScene(
        VenueLayoutDocument(
          nodes: [node],
          canvas: {
            'x': 0,
            'y': 0,
            'width': 100,
            'height': 100,
            'fill': '#FFFFFFFF',
          },
        ),
      );
      final recorder = ui.PictureRecorder();
      LayoutScenePainter(
        scene: scene,
        resources: const {},
        selected: const {},
        scale: 1,
        offset: Offset.zero,
        canvasColor: Colors.white,
        selectionColor: Colors.blue,
      ).paint(Canvas(recorder), const Size(100, 100));
      final image = (await tester.runAsync(
        () => recorder.endRecording().toImage(100, 100),
      ))!;
      final bytes = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      final outlined = [
        for (var i = 0; i < bytes.length; i += 4)
          if (bytes[i] < 250 && bytes[i + 2] > 250) i,
      ].length;
      expect(outlined, width == 0 ? 0 : greaterThan(100));
      image.dispose();
    }
  });
}
