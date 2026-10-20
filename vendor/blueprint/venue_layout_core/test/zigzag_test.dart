import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

List<List<double>> endpoints(VenueLayoutDocument d, String id) {
  final n = d.nodes.firstWhere((n) => n.id == id),
      p = n.properties['points'] as List;
  final m = worldMatrix(d, n);
  return [
    for (final point in [p.first, p.last])
      transformPoint(
        m,
        (point[0] as num).toDouble(),
        (point[1] as num).toDouble(),
      ),
  ];
}

void nearPoints(List<List<double>> a, List<List<double>> b) {
  for (var i = 0; i < a.length; i++) {
    expect(a[i][0], closeTo(b[i][0], 0.003));
    expect(a[i][1], closeTo(b[i][1], 0.003));
  }
}

void main() {
  test('regular zigzag materializes exact endpoints and alternating peaks', () {
    final n = zigzagLine(100, 200, 420, 200),
        d = VenueLayoutDocument(nodes: [n]);
    expect(isZigzagNode(n), isTrue);
    final p = n.properties['points'] as List;
    expect(p.length, 18);
    nearPoints(endpoints(d, n.id), [
      [100, 200],
      [420, 200],
    ]);
    for (var i = 1; i < p.length - 1; i++) {
      expect((p[i][1] as num).abs(), 12);
      expect(p[i][1], i.isOdd ? 12 : -12);
    }
    expect(validateDocument(d), isEmpty);
    expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
  });
  test(
    'nested rotated parameter edits retain world endpoints ID style parent',
    () {
      final parent = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 270,
        y: 220,
        rotation: 31,
      );
      final n = zigzagLine(
        -80,
        -30,
        120,
        50,
        properties: {},
        style: {'stroke': '#FF0000FF'},
      ).copyWith(parentId: parent.id, rotation: 47, label: 'Divider');
      final d = VenueLayoutDocument(nodes: [parent, n]);
      final before = endpoints(d, n.id),
          result = updateZigzag(d, n.id, teeth: 13, amplitude: 18);
      nearPoints(endpoints(result, n.id), before);
      final edited = result.nodes.last;
      expect(edited.id, n.id);
      expect(edited.parentId, parent.id);
      expect(edited.rotation, 47);
      expect(edited.label, 'Divider');
      expect(edited.style['stroke'], '#FF0000FF');
      expect((edited.properties['points'] as List).length, 28);
      expect(validateDocument(result), isEmpty);
      final points = edited.properties['points'] as List;
      final changed = updateZigzag(
        result,
        n.id,
        start: [
          (points.first[0] as num).toDouble() - 30,
          (points.first[1] as num).toDouble() + 20,
        ],
      );
      nearPoints([endpoints(changed, n.id).last], [before.last]);
    },
  );
  test('resize regenerates regular pattern and amplitude metadata', () {
    final n = zigzagLine(100, 100, 420, 100);
    final d = VenueLayoutDocument(nodes: [n]);
    final r = resizeNode(d, n.id, 640, 48), changed = r.nodes.single;
    expect(changed.width, 640);
    expect(changed.height, 48);
    expect(changed.properties['zigzagAmplitude'], 24);
    expect(validateDocument(r), isEmpty);
    final diagonal = zigzagLine(0, 0, 240, 160);
    final dr = resizeNode(
      VenueLayoutDocument(nodes: [diagonal]),
      diagonal.id,
      400,
      100,
    );
    expect(validateDocument(dr), isEmpty);
  });
  test('freeform vertex operations clear generated metadata', () {
    final n = zigzagLine(100, 100, 420, 100),
        d = VenueLayoutDocument(nodes: [n]);
    for (final r in [
      updatePathVertex(d, n.id, 2, -100, 20),
      insertPathVertex(d, n.id, 1, -100, 20),
      removePathVertex(d, n.id, 2),
    ]) {
      expect(isZigzagNode(r.nodes.single), isFalse);
      expect(r.nodes.single.properties.containsKey('zigzagTeeth'), isFalse);
      expect(r.nodes.single.properties.containsKey('zigzagAmplitude'), isFalse);
      expect(validateDocument(r), isEmpty);
    }
  });
  test('strict parameter type budget and geometry validation', () {
    final n = zigzagLine(0, 0, 320, 0);
    for (final props in [
      {...n.properties, 'zigzagTeeth': 1.5},
      {...n.properties, 'zigzagTeeth': 256},
      {...n.properties, 'zigzagAmplitude': double.nan},
      {...n.properties, 'zigzagAmplitude': -1},
      {...n.properties, 'pathPattern': 'sine'},
      {...n.properties, 'zigzagAmplitude': 13},
    ]) {
      expect(
        validateDocument(
          VenueLayoutDocument(nodes: [n.copyWith(properties: props)]),
        ),
        isNotEmpty,
      );
    }
    expect(() => zigzagLine(0, 0, 100, 0, teeth: 256), throwsRangeError);
    expect(() => zigzagLine(0, 0, 0, 0), throwsArgumentError);
    expect(
      () => zigzagLine(0, 0, 100, 0, amplitude: double.infinity),
      throwsArgumentError,
    );
    expect(
      (zigzagLine(0, 0, 100, 0, teeth: 255).properties['points'] as List)
          .length,
      512,
    );
    final ordinary = shapeFromPoints('polyline', [
      [0, 0],
      [20, 30],
      [90, 10],
    ]);
    expect(validateDocument(VenueLayoutDocument(nodes: [ordinary])), isEmpty);
  });
  test('ancestor and node locks reject updates atomically', () {
    final parent = LayoutNode(id: newLayoutId(), kind: 'group', locked: true);
    final n = zigzagLine(0, 0, 200, 0).copyWith(parentId: parent.id);
    final d = VenueLayoutDocument(nodes: [parent, n]);
    expect(() => updateZigzag(d, n.id, teeth: 4), throwsStateError);
    expect(() => resizeNode(d, n.id, 300, 30), throwsStateError);
    expect(n.properties['zigzagTeeth'], 8);
  });
}
