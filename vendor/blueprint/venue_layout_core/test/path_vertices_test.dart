import 'dart:math';

import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

List<double> vertex(VenueLayoutDocument d, LayoutNode n, int i) {
  final p = (n.properties['points'] as List)[i] as List;
  return transformPoint(
    worldMatrices(d)[n.id]!,
    (p[0] as num).toDouble(),
    (p[1] as num).toDouble(),
  );
}

void main() {
  test('implicit line gains a bend and retains endpoints and styling', () {
    final line = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 200,
          y: 200,
          width: 100,
          height: 1,
          z: 4,
          label: 'Link',
          properties: {'shape': 'line'},
          style: {'stroke': '#123456FF', 'strokeWidth': 2, 'opacity': .7},
        ),
        d = VenueLayoutDocument(nodes: [line]),
        result = insertPathVertex(d, line.id, 0, 0, 40),
        edited = result.nodes.single;
    expect(edited.id, line.id);
    expect(edited.properties['shape'], 'polyline');
    expect(edited.style['stroke'], line.style['stroke']);
    expect(edited.style['opacity'], .7);
    expect(edited.z, 4);
    expect(edited.label, 'Link');
    expect(vertex(result, edited, 0), [150, 200]);
    expect(vertex(result, edited, 1), [200, 240]);
    expect(vertex(result, edited, 2), [250, 200]);
    expect(edited.width, 100);
    expect(edited.height, 40);
    expect(result.canvas, d.canvas);
    expect(validateDocument(result), isEmpty);
    final removed = removePathVertex(result, line.id, 1),
        straight = removed.nodes.single;
    expect(straight.properties['shape'], 'polyline');
    expect(vertex(removed, straight, 0), [150, 200]);
    expect(vertex(removed, straight, 1), [250, 200]);
  });

  test('rotated nested path insertion preserves untouched world vertices', () {
    final parent = LayoutNode(
          id: newLayoutId(),
          kind: 'group',
          x: 400,
          y: 300,
          rotation: 17,
        ),
        path = shapeFromPoints('polyline', [
          [-50, -30],
          [0, 60],
          [50, -30],
        ]).copyWith(parentId: parent.id, x: 100, y: 80, rotation: 43),
        d = VenueLayoutDocument(nodes: [parent, path]),
        expectedBend = transformPoint(worldMatrices(d)[path.id]!, -40, 10),
        result = insertPathVertex(d, path.id, 0, -40, 10),
        edited = result.nodes.firstWhere((n) => n.id == path.id);
    for (final (oldIndex, newIndex) in [(0, 0), (1, 2), (2, 3)]) {
      final old = vertex(d, path, oldIndex),
          next = vertex(result, edited, newIndex);
      expect(next[0], closeTo(old[0], .002));
      expect(next[1], closeTo(old[1], .002));
    }
    final bend = vertex(result, edited, 1);
    expect(bend[0], closeTo(expectedBend[0], .002));
    expect(bend[1], closeTo(expectedBend[1], .002));
    expect(edited.parentId, parent.id);
    expect(edited.rotation, path.rotation);
    final removed = removePathVertex(result, path.id, 1),
        restored = removed.nodes.firstWhere((n) => n.id == path.id);
    for (var i = 0; i < 3; i++) {
      expect(
        vertex(removed, restored, i)[0],
        closeTo(vertex(d, path, i)[0], .003),
      );
      expect(
        vertex(removed, restored, i)[1],
        closeTo(vertex(d, path, i)[1], .003),
      );
    }
  });

  test(
    'polygon closing edge accepts insert and removal keeps minimum of three',
    () {
      final path = shapeFromPoints('polygon', [
            [0, 0],
            [100, 0],
            [50, 100],
          ]),
          d = VenueLayoutDocument(nodes: [path]),
          result = insertPathVertex(d, path.id, 2, -30, 0);
      expect((result.nodes.single.properties['points'] as List).length, 4);
      for (var i = 0; i < 3; i++) {
        expect(vertex(result, result.nodes.single, i), vertex(d, path, i));
      }
      final removed = removePathVertex(result, path.id, 3);
      expect((removed.nodes.single.properties['points'] as List).length, 3);
      expect(() => removePathVertex(removed, path.id, 0), throwsStateError);
      expect(validateDocument(result), isEmpty);
    },
  );

  test(
    'arrow stays arrow and endpoint removal preserves remaining geometry',
    () {
      final path = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            x: 200,
            y: 200,
            width: 100,
            height: 1,
            properties: {'shape': 'arrow'},
          ),
          d = VenueLayoutDocument(nodes: [path]),
          result = insertPathVertex(d, path.id, 0, 0, 40);
      expect(result.nodes.single.properties['shape'], 'arrow');
      final oldTip = vertex(result, result.nodes.single, 2),
          removed = removePathVertex(result, path.id, 0);
      expect(removed.nodes.single.properties['shape'], 'arrow');
      expect(vertex(removed, removed.nodes.single, 1), oldTip);
      expect(() => removePathVertex(removed, path.id, 0), throwsStateError);
    },
  );

  test(
    'locked objects, finite coordinates, indices and vertex budget reject atomically',
    () {
      final path = shapeFromPoints('line', [
            [0, 0],
            [100, 0],
          ]),
          d = VenueLayoutDocument(nodes: [path]),
          snapshot = d.toJson();
      for (final invalid in [double.nan, double.infinity, 1e20]) {
        expect(
          () => insertPathVertex(d, path.id, 0, invalid, 10),
          throwsArgumentError,
        );
      }
      expect(() => insertPathVertex(d, path.id, 1, 50, 50), throwsRangeError);
      expect(() => removePathVertex(d, path.id, 2), throwsRangeError);
      expect(() => removePathVertex(d, path.id, 0), throwsStateError);
      final parent = LayoutNode(id: newLayoutId(), kind: 'group', locked: true),
          locked = d.copyWith(
            nodes: [
              parent,
              path.copyWith(parentId: parent.id),
            ],
          );
      expect(
        () => insertPathVertex(locked, path.id, 0, 50, 50),
        throwsStateError,
      );
      final many = shapeFromPoints(
        'polyline',
        List.generate(512, (i) => [i.toDouble(), sin(i.toDouble())]),
      );
      expect(
        () => insertPathVertex(
          VenueLayoutDocument(nodes: [many]),
          many.id,
          0,
          1,
          1,
        ),
        throwsStateError,
      );
      expect(d.toJson(), snapshot);
    },
  );
}
