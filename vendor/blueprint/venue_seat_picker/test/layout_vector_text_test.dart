import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'view paints whole-text paths without native fonts and editing requires a fresh resource',
    (tester) async {
      final fixture =
          jsonDecode(
                File(
                  'web/test/fixtures/canonical_rendering.json',
                ).readAsStringSync(),
              )
              as Map;
      final source = VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(fixture['document']),
      );
      final node = source.nodes.firstWhere((n) => n.kind == 'text');
      final document = source.copyWith(
        nodes: [node],
        attachments: [],
        selectionUnits: [],
        sections: [],
        presets: [],
      );
      final c = VenueLayoutController(
        document,
        resources: Map<String, dynamic>.from(fixture['resources']),
      );
      addTearDown(c.dispose);
      final before = compileScene(document, resources: c.resources);
      expect(before['issues'], isEmpty);
      final glyph =
          (before['items'] as List).singleWhere(
                (item) => item['kind'] == 'glyphs',
              )
              as Map;
      expect(glyph['path'], isNotEmpty);
      expect(
        (before['items'] as List).any((item) => item['kind'] == 'text'),
        isFalse,
      );
      // No font loader or native font bytes are used by the view painter.
      final recorder = ui.PictureRecorder();
      LayoutScenePainter(
        scene: before,
        resources: c.resources,
        selected: const {},
        scale: 1,
        offset: Offset.zero,
        canvasColor: Colors.white,
        selectionColor: Colors.blue,
      ).paint(Canvas(recorder), const Size(400, 400));
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(400, 400)))!;
      final pixels = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!.buffer.asUint8List();
      var ink = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] < 100 && pixels[i + 1] < 100 && pixels[i + 2] < 100) {
          ink++;
        }
      }
      expect(ink, greaterThan(50));
      image.dispose();
      picture.dispose();
      c.updateNode(
        node.copyWith(
          properties: {...node.properties, 'text': 'Changed source'},
        ),
      );
      expect(c.document.nodes.single.properties['text'], 'Changed source');
      final pending = compileScene(c.document, resources: c.resources);
      expect(pending['issues'], isNotEmpty);
      expect(
        (pending['items'] as List).where((item) => item['kind'] == 'glyphs'),
        isEmpty,
      );
      c.undo();
      expect(c.document.toJson(), document.toJson());
      expect(
        compileScene(c.document, resources: c.resources)['items'],
        before['items'],
      );
    },
  );
}
