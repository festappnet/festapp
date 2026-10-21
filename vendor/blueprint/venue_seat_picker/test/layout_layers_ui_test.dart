import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  test('canvas magnets use screen distance and preserve free movement', () {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 50,
      y: 60,
      width: 20,
      height: 20,
    );
    final d = VenueLayoutDocument.empty().copyWith(
      nodes: [node],
      canvas: {
        'x': 0,
        'y': 0,
        'width': 200,
        'height': 200,
        'fill': '#FFFFFFFF',
      },
    );
    final zoomedOut = snapTranslation(d, {node.id}, 39, 0, zoom: .5);
    expect(zoomedOut.dx, 40); // Right edge reaches the canvas center.
    expect(zoomedOut.guides, contains(containsPair('value', 100.0)));
    final nearCenter = snapTranslation(d, {node.id}, 46, 0, zoom: 1);
    expect(nearCenter.dx, 50);
    final zoomedIn = snapTranslation(d, {node.id}, 46, 0, zoom: 2);
    expect(zoomedIn.dx, 46); // Four world units are eight screen pixels.
    expect(zoomedIn.guides, isEmpty);
    final disabled = snapTranslation(
      d,
      {node.id},
      46,
      0,
      zoom: .5,
      disabled: true,
    );
    expect(disabled.dx, 46);
    expect(disabled.guides, isEmpty);
  });
  test(
    'transient foreground raises descendant body and glyph without document mutation',
    () async {
      final a = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 100,
        y: 100,
        width: 80,
        height: 80,
        properties: {'shape': 'rectangle'},
        style: {'fill': '#FF0000FF'},
      );
      final b = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 100,
        y: 100,
        width: 80,
        height: 80,
        z: 1,
        properties: {'shape': 'rectangle'},
        style: {'fill': '#0000FFFF'},
      );
      final document = VenueLayoutDocument.empty().copyWith(nodes: [a, b]);
      final scene = compileScene(document);
      final items = (scene['items'] as List);
      final body = Map<String, dynamic>.from(
        items.firstWhere((i) => i['id'] == a.id),
      );
      // Synthetic glyph item uses the same node ownership contract as compiler glyphs.
      final glyph = {
        ...body,
        'id': '${a.id}:glyph',
        'nodeId': a.id,
        'fill': '#00FF00FF',
      };
      final display = {
        ...scene,
        'items': [body, glyph, ...items.where((i) => i['id'] != a.id)],
      };
      Future<List<int>> pixel(Set<String> foreground) async {
        final recorder = ui.PictureRecorder();
        LayoutScenePainter(
          scene: display,
          resources: const {},
          selected: const {},
          transientForegroundIds: foreground,
          scale: 1,
          offset: Offset.zero,
          canvasColor: Colors.white,
          selectionColor: Colors.blue,
        ).paint(Canvas(recorder), const Size(200, 200));
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 200);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final result = data.sublist(
          (100 * 200 + 100) * 4,
          (100 * 200 + 100) * 4 + 4,
        );
        image.dispose();
        picture.dispose();
        return result;
      }

      expect(await pixel({}), [0, 0, 255, 255]);
      expect(await pixel({a.id}), [0, 255, 0, 255]);
      expect(await pixel({}), [0, 0, 255, 255]);
      expect(document.nodes.map((n) => n.id), [a.id, b.id]);
      expect(a.z, 0);
    },
  );

  testWidgets('layer controls move a complete group and undo its order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final group = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      label: 'Assembly',
    );
    final child = LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      parentId: group.id,
      label: 'Caption',
      properties: {'text': 'Caption'},
    );
    final other = LayoutNode(id: newLayoutId(), kind: 'shape', z: 5);
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [group, child, other]),
    );
    addTearDown(c.dispose);
    c.select({group.id});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: c,
            builder: (_, _) => LayoutInspector(
              controller: c,
              cornerPivot: false,
              onPivotChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Layers'));
    await tester.tap(find.text('Layers'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Bring to front'));
    await tester.tap(find.byTooltip('Bring to front'));
    await tester.pump();
    expect(orderedNodes(c.document).map((n) => n.id), [
      other.id,
      group.id,
      child.id,
    ]);
    expect(
      c.document.nodes.singleWhere((n) => n.id == child.id).parentId,
      group.id,
    );
    c.undo();
    expect(orderedNodes(c.document).map((n) => n.id), [
      group.id,
      child.id,
      other.id,
    ]);
  });
}
