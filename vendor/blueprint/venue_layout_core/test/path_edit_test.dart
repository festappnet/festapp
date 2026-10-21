import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

List<double> point(VenueLayoutDocument d, LayoutNode node, int index) {
  final p = (node.properties['points'] as List)[index] as List;
  return transformPoint(
    worldMatrices(d)[node.id]!,
    (p[0] as num).toDouble(),
    (p[1] as num).toDouble(),
  );
}

void main() {
  test('resizing explicit path scales the actual rendered endpoints', () {
    final n = shapeFromPoints(
      'line',
      [
        [100, 100],
        [200, 200],
      ],
      properties: {},
      style: {'stroke': '#123456FF', 'strokeWidth': 2},
    );
    final d = VenueLayoutDocument(nodes: [n]);
    final result = resizeNode(d, n.id, 200, 50), resized = result.nodes.single;
    expect(resized.width, 200);
    expect(resized.height, 50);
    expect(point(result, resized, 0), [50, 125]);
    expect(point(result, resized, 1), [250, 175]);
    expect(resized.id, n.id);
    expect(resized.style['stroke'], n.style['stroke']);
    expect(nodePath(resized), [
      ['M', -100, -25],
      ['L', 100, 25],
    ]);
    expect(validateDocument(result), isEmpty);
  });

  test('polygon and polyline points resize with dimensions', () {
    for (final shape in ['polygon', 'polyline', 'arrow']) {
      final n = shapeFromPoints(shape, [
            [0, 0],
            [100, 0],
            [50, 100],
          ]),
          d = VenueLayoutDocument(nodes: [n]),
          result = resizeNode(d, n.id, 200, 200);
      expect(result.nodes.single.properties['points'], [
        [-100, -100],
        [100, -100],
        [0, 100],
      ]);
      expect(validateDocument(result), isEmpty);
    }
  });

  test(
    'editing a vertex under rotated parent preserves every other world vertex',
    () {
      final root = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 500,
        y: 400,
        rotation: 31,
      );
      final n = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: root.id,
        x: 100,
        y: 80,
        rotation: 42,
        width: 100,
        height: 90,
        z: 7,
        label: 'Custom path',
        properties: {
          'shape': 'polyline',
          'points': [
            [-50, -30],
            [0, 60],
            [50, -30],
          ],
        },
        style: {'stroke': '#123456FF', 'strokeWidth': 3},
      );
      final d = VenueLayoutDocument(nodes: [root, n]),
          expected = transformPoint(worldMatrices(d)[n.id]!, 40, 100),
          result = updatePathVertex(d, n.id, 1, 40, 100),
          edited = result.nodes.firstWhere((v) => v.id == n.id);
      for (final index in [0, 2]) {
        final before = point(d, n, index), after = point(result, edited, index);
        expect(after[0], closeTo(before[0], .002));
        expect(after[1], closeTo(before[1], .002));
      }
      final changed = point(result, edited, 1);
      expect(changed[0], closeTo(expected[0], .002));
      expect(changed[1], closeTo(expected[1], .002));
      expect(edited.width, 100);
      expect(edited.height, 130);
      expect(edited.parentId, root.id);
      expect(edited.rotation, n.rotation);
      expect(edited.z, n.z);
      expect(edited.label, n.label);
      expect(edited.locked, n.locked);
      expect(edited.style['stroke'], n.style['stroke']);
      expect(result.nodes.first, same(root));
      expect(validateDocument(result), isEmpty);
    },
  );

  test('editing implicit line or arrow materializes normalized endpoints', () {
    for (final shape in ['line', 'arrow']) {
      final n = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            x: 200,
            y: 200,
            width: 100,
            height: 1,
            properties: {'shape': shape},
          ),
          result = updatePathVertex(
            VenueLayoutDocument(nodes: [n]),
            n.id,
            1,
            90,
            40,
          ),
          edited = result.nodes.single;
      expect(point(result, edited, 0), [150, 200]);
      expect(point(result, edited, 1), [290, 240]);
      expect(edited.width, 140);
      expect(edited.height, 40);
      expect(validateDocument(result), isEmpty);
    }
  });

  test('table resize retains chair count and manual geometry', () {
    final original = tableLayout(shape: 'rect', count: 6),
        table = original.nodes.firstWhere((n) => n.kind == 'table'),
        seat = original.nodes.firstWhere((n) => n.kind == 'seat');
    var d = original.copyWith(
      nodes: original.nodes
          .map(
            (n) => n.id == seat.id
                ? n.copyWith(x: 100, properties: n.properties)
                : n,
          )
          .toList(),
    );
    d = d.copyWith(
      attachments: [
        for (final a in d.attachments)
          a['seatId'] == seat.id
              ? {
                  ...a,
                  'placement': {'mode': 'free'},
                }
              : a,
      ],
    );
    final result = resizeNode(d, table.id, 240, 120);
    expect(result.nodes.where((n) => n.kind == 'seat').length, 6);
    expect(
      result.nodes.map((n) => n.id).toSet(),
      d.nodes.map((n) => n.id).toSet(),
    );
    expect(
      result.nodes.firstWhere((n) => n.id == seat.id).toJson(),
      d.nodes.firstWhere((n) => n.id == seat.id).toJson(),
    );
  });

  test(
    'path updates validate finite coordinates, indices, shape and locks',
    () {
      final n = shapeFromPoints('line', [
            [0, 0],
            [100, 0],
          ]),
          d = VenueLayoutDocument(nodes: [n]);
      for (final invalid in [double.nan, double.infinity, 1e20]) {
        expect(
          () => updatePathVertex(d, n.id, 0, invalid, 0),
          throwsArgumentError,
        );
      }
      expect(() => updatePathVertex(d, n.id, 3, 0, 0), throwsRangeError);
      expect(() => resizeNode(d, n.id, double.nan, 100), throwsArgumentError);
      final locked = d.copyWith(nodes: [n.copyWith(locked: true)]);
      expect(() => updatePathVertex(locked, n.id, 0, 10, 10), throwsStateError);
      final rect = n.copyWith(properties: {'shape': 'rect'});
      expect(
        () => updatePathVertex(d.copyWith(nodes: [rect]), n.id, 0, 10, 10),
        throwsArgumentError,
      );
    },
  );
}
