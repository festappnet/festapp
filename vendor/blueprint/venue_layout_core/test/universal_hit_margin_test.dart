import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'long arrow head uses rendered geometry for exact and tolerant hits',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 200,
        y: 127,
        width: 100,
        height: 1,
        properties: {'shape': 'arrow', 'arrowHeadLength': 180},
        style: {'strokeWidth': 4},
      );
      for (final rotation in [0.0, 37.0]) {
        final parent = LayoutNode(
          id: newLayoutId(),
          kind: 'group',
          x: 500,
          y: 500,
          rotation: rotation,
        );
        final child = node.copyWith(parentId: parent.id, rotation: rotation);
        final d = VenueLayoutDocument(nodes: [parent, child]);
        final matrix = worldMatrix(d, child);
        final x = 50 - 90 * math.cos(.5), y = 90 * math.sin(.5);
        final point = transformPoint(matrix, x, y);
        expect(hitTest(d, point[0], point[1], tolerance: 0), child.id);
        final index = spatialIndexFor(d);
        expect(index.resolveTap(point[0], point[1], tolerance: 0), child.id);
        for (final zoom in [.25, 1.0, 3.0]) {
          for (final px in [6.0, 9.0]) {
            final distance = 2 + px / zoom;
            final near = transformPoint(
              matrix,
              x + math.sin(.5) * distance,
              y + math.cos(.5) * distance,
            );
            expect(
              index.resolveTap(near[0], near[1], tolerance: 8 / zoom),
              px < 8 ? child.id : isNull,
            );
          }
        }
      }
    },
  );
  for (final shape in ['rectangle', 'ellipse', 'polygon']) {
    test(
      '$shape includes its visible thick stroke and radial margin across cells',
      () {
        final node = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 100,
          y: 100,
          width: 40,
          height: 40,
          properties: {
            'shape': shape,
            if (shape == 'polygon')
              'points': [
                [-20, -20],
                [20, -20],
                [20, 20],
                [-20, 20],
              ],
          },
          style: {'strokeWidth': 32, 'cornerRadius': 0},
        );
        final index = spatialIndexFor(VenueLayoutDocument(nodes: [node]));
        expect(index.resolveTap(135, 100, tolerance: 0), node.id);
        for (final zoom in [.25, 1.0, 3.0]) {
          expect(
            index.resolveTap(136 + 6 / zoom, 100, tolerance: 8 / zoom),
            node.id,
          );
          expect(
            index.resolveTap(136 + 9 / zoom, 100, tolerance: 8 / zoom),
            isNull,
          );
        }
      },
    );
  }
}
