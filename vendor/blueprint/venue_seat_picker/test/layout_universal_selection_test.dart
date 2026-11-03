import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

const paletteKinds = [
  'Seat',
  'Table',
  'Round table',
  'Rows',
  'Arc',
  'Standing',
  'Couch',
  'Bar',
  'Draw table',
  'Draw bar',
  'Bus',
  'Double-decker bus',
  'Compartments',
  'Text',
  'Rectangle',
  'Ellipse',
  'Line',
  'Arrow',
  'Polyline',
  'Polygon',
  'Image',
  'Vector',
  'Preset',
];

void main() {
  for (final kind in paletteKinds) {
    testWidgets('$kind insertion shares the visible 8 pixel selection margin', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final presetId = newLayoutId();
      final assetRef = 'image:${'a' * 64}';
      final fragment = tableLayout(shape: 'rect', count: 0);
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': 4000,
            'height': 4000,
            'fill': '#FFFFFFFF',
          },
          presets: [
            {'id': presetId, 'title': 'Table', 'document': fragment.toJson()},
          ],
        ),
        resources: {
          'protocol': 2,
          'fontFamilies': <String, dynamic>{},
          'textLayouts': <String, dynamic>{},
          'numberSymbols': <String, dynamic>{},
          'assets': {
            assetRef: {
              'hash': 'a' * 64,
              'width': 200,
              'height': 100,
              'mimeType': 'image/png',
              'byteLength': 75,
              'url':
                  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEklEQVR4nGP4z8DwHwyBNBgAAEnICff5q7YNAAAAAElFTkSuQmCC',
            },
          },
        },
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
      final finder = find.byType(LayoutSceneSurface);
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(finder);
      if (kind == 'Image') {
        expect(
          c.insertBitmapAsset(
            assetRef,
            x: 2000,
            y: 2000,
            width: 200,
            height: 100,
          ),
          isTrue,
        );
      } else if (kind == 'Vector') {
        expect(
          c.insertVectorGraphic(
            LayoutVectorGraphic.fromJson({
              'version': 1,
              'width': 200,
              'height': 100,
              'commands': <Object>[],
            }),
            x: 2000,
            y: 2000,
            width: 200,
            height: 100,
          ),
          isTrue,
        );
      } else {
        surface().onDrop!(
          kind == 'Preset' ? 'preset:$presetId' : kind,
          const Offset(2000, 2000),
        );
      }
      await tester.pumpAndSettle();
      if (kind == 'Text') {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
      }
      expect(c.error, isNull);
      expect(c.document.nodes, isNotEmpty);
      final nodes = {for (final n in c.document.nodes) n.id: n};
      Offset? edge;
      double edgeStroke = 0;
      for (final node in c.document.nodes.where((n) => n.kind != 'group')) {
        final props = effectiveNodeProperties(c.document, node);
        final styled = node.copyWith(properties: props);
        final open = const [
          'line',
          'polyline',
          'arrow',
        ].contains(props['shape']);
        final points = open
            ? nodePath(styled)
                  .where((c) => c[0] == 'M' || c[0] == 'L')
                  .map(
                    (c) => [(c[1] as num).toDouble(), (c[2] as num).toDouble()],
                  )
            : nodeOutlineContours(
                styled,
                parent: nodes[node.parentId],
              ).expand((c) => c);
        final matrix = worldMatrix(c.document, node);
        final stroke = (props['strokeWidth'] as num? ?? 0).toDouble() / 2;
        for (final point in points) {
          final world = transformPoint(matrix, point[0], point[1]);
          if (edge == null || world[0] + stroke > edge!.dx + edgeStroke) {
            edge = Offset(world[0], world[1]);
            edgeStroke = stroke;
          }
        }
      }
      expect(edge, isNotNull);
      final original = c.document.toJson();
      for (final scale in [.25, 1.0, 3.0]) {
        surface().onViewportScaleChanged!(scale);
        c.select({});
        surface().onSelectDown!(edge!);
        surface().onTap!(edge!);
        final direct = {...c.selection};
        expect(direct, isNotEmpty);
        c.select({});
        final near = edge! + Offset(edgeStroke + 6 / scale, 0);
        surface().onSelectDown!(near);
        expect(
          c.selection,
          direct,
          reason: 'Near down must own the same object at zoom $scale',
        );
        surface().onTap!(near);
        expect(c.selection, direct);
        c.select({});
        final far = edge! + Offset(edgeStroke + 9 / scale, 0);
        surface().onSelectDown!(far);
        expect(
          c.selection,
          isEmpty,
          reason: 'The margin stops beyond 8 pixels at zoom $scale',
        );
        surface().onTap!(far);
        expect(c.selection, isEmpty);
      }
      expect(c.document.toJson(), original);
    });
  }

  for (final pointer in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    testWidgets(
      'near arrow $pointer drag moves the object instead of navigating',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final node = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 400,
          y: 300,
          width: 200,
          height: 1,
          properties: {'shape': 'arrow', 'arrowHeadLength': 40},
          style: {'strokeWidth': 2},
        );
        final c = VenueLayoutController(
          VenueLayoutDocument.empty().copyWith(
            canvas: {
              'x': 0,
              'y': 0,
              'width': 800,
              'height': 600,
              'fill': '#FFFFFFFF',
            },
            nodes: [node],
          ),
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
        final finder = find.byType(LayoutSceneSurface);
        final painter = tester
            .widgetList<CustomPaint>(
              find.descendant(of: finder, matching: find.byType(CustomPaint)),
            )
            .map((w) => w.painter)
            .whereType<LayoutScenePainter>()
            .single;
        final camera = painter.camera!.value.clone();
        final zoom = painter.scale * camera.entry(0, 0);
        final near =
            tester.getTopLeft(finder) +
            MatrixUtils.transformPoint(
              camera,
              painter.offset + Offset(400, 301 + 6 / zoom) * painter.scale,
            );
        final gesture = await tester.startGesture(near, kind: pointer);
        await gesture.moveBy(const Offset(45, 25));
        await gesture.moveBy(const Offset(20, 10));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(c.selection, {node.id});
        expect(c.document.nodes.single.x, isNot(node.x));
        expect(painter.camera!.value, camera);
        c.undo();
        expect(c.document.nodes.single, node);
      },
    );
  }
}
