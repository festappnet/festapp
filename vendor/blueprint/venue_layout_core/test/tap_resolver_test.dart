import 'dart:math';

import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

LayoutNode box(
  String id, {
  String kind = 'table',
  double x = 100,
  double y = 100,
  double rotation = 0,
  int z = 0,
  Map<String, dynamic> properties = const {},
}) => LayoutNode(
  id: id,
  kind: kind,
  x: x,
  y: y,
  width: 40,
  height: 40,
  rotation: rotation,
  z: z,
  properties: properties,
  style: {
    if (properties['cornerRadius'] != null)
      'cornerRadius': properties['cornerRadius'],
    if (properties['strokeWidth'] != null)
      'strokeWidth': properties['strokeWidth'],
  },
);

void main() {
  for (final kind in ['seat', 'table', 'text', 'furniture']) {
    for (final zoom in [.5, 1.0, 2.0]) {
      test('$kind radial 7/8/9px slop at zoom $zoom', () {
        final node = box('target', kind: kind);
        final document = VenueLayoutDocument(nodes: [node]);
        final index = spatialIndexFor(document);
        // Shared outline, including non-rectangular seat/text rendering.
        final outline = nodeOutlineContours(node.copyWith(
          properties: effectiveNodeProperties(document, node),
        ))
            .expand((ring) => ring)
            .toList();
        final edge = outline.reduce((a, b) => a[0] > b[0] ? a : b);
        for (final pixels in [7.0, 8.0, 9.0]) {
          expect(
            index.resolveTap(
              100 + edge[0] + pixels / zoom,
              100 + edge[1],
              tolerance: 8 / zoom,
            ),
            pixels <= 8 ? node.id : isNull,
          );
        }
      });
    }
  }
  test('radial corners, direct neighbor, nearest boundary and paint ties', () {
    final table = box('table', properties: {'cornerRadius': 0});
    final index = spatialIndexFor(VenueLayoutDocument(nodes: [table]));
    expect(index.resolveTap(125, 125, tolerance: 8), table.id);
    expect(index.resolveTap(126, 126, tolerance: 8), isNull);
    final near = box('near', x: 150, kind: 'seat');
    final both = spatialIndexFor(VenueLayoutDocument(nodes: [table, near]));
    expect(both.resolveTap(132, 100, tolerance: 20), near.id);
    expect(both.resolveTap(127, 100, tolerance: 8), near.id);
    final tied = spatialIndexFor(
      VenueLayoutDocument(nodes: [box('a'), box('b')]),
    );
    expect(tied.resolveTap(125, 100, tolerance: 8), 'b');
    expect(tied.resolveTap(100, 100, tolerance: 8), 'b');
  });
  test('blockers stop fallback, ignored decoration and mapped groups', () {
    final doc = VenueLayoutDocument(
      nodes: [box('free'), box('blocked', x: 150), box('decoration', x: 130)],
    );
    LayoutTapDisposition classify(LayoutNode n) => n.id == 'decoration'
        ? LayoutTapDisposition.ignore
        : n.id == 'blocked'
        ? LayoutTapDisposition.block
        : LayoutTapDisposition.activate;
    final index = spatialIndexFor(doc);
    expect(
      index.resolveTap(128, 100, tolerance: 10, classify: classify),
      'blocked',
    );
    expect(
      index.resolveTap(
        115,
        100,
        tolerance: 10,
        classify: classify,
        selectionTarget: (_) => 'group',
      ),
      'group',
    );
  });
  test(
    'locked overlap retains paint priority and decoration maps to assembly',
    () {
      final locked = box('locked', z: 2).copyWith(locked: true);
      final index = spatialIndexFor(
        VenueLayoutDocument(nodes: [box('under'), locked]),
      );
      expect(index.resolveTap(100, 100, tolerance: 8), locked.id);
      expect(index.resolveTap(125, 100, tolerance: 8), locked.id);
      final group = LayoutNode(
        id: 'group',
        kind: 'group',
        assembly: {'kind': 'rows'},
      );
      final decoration = box(
        'decoration',
        properties: {'role': 'decoration'},
      ).copyWith(parentId: group.id);
      expect(
        spatialIndexFor(VenueLayoutDocument(nodes: [group, decoration]))
            .resolveTap(125, 100, tolerance: 8),
        group.id,
      );
      expect(() => index.resolveTap(0, 0, tolerance: -1), throwsArgumentError);
    },
  );
  test('nested rotation uses outline, holes and rendered line stroke', () {
    final root = LayoutNode(
      id: 'root',
      kind: 'group',
      x: 100,
      y: 100,
      rotation: 37,
    );
    final child = box('child', x: 0, y: 0).copyWith(parentId: root.id);
    final index = spatialIndexFor(VenueLayoutDocument(nodes: [root, child]));
    expect(
      index.resolveTap(125, 125, tolerance: 8),
      isNull,
      reason: 'A rotated bounding box is not the real outline',
    );
    final angle = 37 * pi / 180;
    expect(
      index.resolveTap(
        100 + cos(angle) * 127 / 5,
        100 + sin(angle) * 127 / 5,
        tolerance: 8,
      ),
      child.id,
    );
    final hole = box(
      'hole',
      properties: {
        'holes': [
          [
            [-10, -10],
            [10, -10],
            [10, 10],
            [-10, 10],
          ],
        ],
      },
    );
    final holes = spatialIndexFor(VenueLayoutDocument(nodes: [hole]));
    expect(holes.resolveTap(100, 100, tolerance: 8), isNull);
    expect(holes.resolveTap(103, 100, tolerance: 8), hole.id);
    final line = box('line', properties: {'shape': 'line', 'strokeWidth': 4});
    final strokes = spatialIndexFor(VenueLayoutDocument(nodes: [line]));
    expect(strokes.resolveTap(100, 110, tolerance: 8), line.id);
    expect(strokes.resolveTap(100, 110.01, tolerance: 8), isNull);
    expect(strokes.resolveTap(127, 100, tolerance: 8), line.id);
    expect(strokes.resolveTap(129, 109, tolerance: 8), isNull);
  });
}
