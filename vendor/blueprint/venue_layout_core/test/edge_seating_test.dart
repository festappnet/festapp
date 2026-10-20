import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument hall({int count = 4, String shape = 'rect'}) {
  final d = tableLayout(
    shape: shape,
    count: count,
    x: 250,
    y: 50,
    width: 180,
    height: 100,
  );
  return d.copyWith(canvas: {...d.canvas, 'width': 500, 'height': 400});
}

bool inside(VenueLayoutDocument d, LayoutNode n) {
  final b = nodeBounds(d, n), c = d.canvas;
  return b['x']! >= (c['x'] as num) - 1e-6 &&
      b['y']! >= (c['y'] as num) - 1e-6 &&
      b['x']! + b['width']! <= (c['x'] as num) + (c['width'] as num) + 1e-6 &&
      b['y']! + b['height']! <= (c['y'] as num) + (c['height'] as num) + 1e-6;
}

void main() {
  test(
    'bounded movement handles rotated nesting, multiple objects and corners',
    () {
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 200,
        y: 200,
        rotation: 37,
      );
      final child = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        parentId: group.id,
        x: 60,
        y: 0,
        width: 100,
        height: 50,
      );
      final other = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 100,
        y: 100,
        width: 80,
        height: 60,
      );
      final before = hall(count: 0).copyWith(nodes: [group, child, other]);
      final result = moveLayoutWithinCanvas(
        before,
        {group.id, other.id},
        dx: 900,
        dy: -900,
      );
      expect(
        result.nodes
            .where((n) => n.kind != 'group')
            .every((n) => inside(result, n)),
        isTrue,
      );
      final a = worldMatrix(before, child), b = worldMatrix(result, child);
      final movedOther = result.nodes.firstWhere((n) => n.id == other.id);
      expect(b[4] - a[4], closeTo(movedOther.x - other.x, .001));
      expect(b[5] - a[5], closeTo(movedOther.y - other.y, .001));
      expect(result.canvas, before.canvas);
    },
  );

  test(
    'bounded insertion recovers origin fragment and preserves locked behavior',
    () {
      final item = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: -100,
        y: -100,
        width: 40,
        height: 40,
      );
      final before = hall(count: 0).copyWith(nodes: [item]);
      final result = moveLayoutWithinCanvas(
        before,
        {item.id},
        dx: 900,
        dy: 900,
      );
      expect(result.nodes.single.x, 480);
      expect(result.nodes.single.y, 380);
      expect(inside(result, result.nodes.single), isTrue);
      final locked = before.copyWith(nodes: [item.copyWith(locked: true)]);
      expect(
        () => moveLayoutWithinCanvas(locked, {item.id}, dx: 100),
        throwsStateError,
      );
    },
  );

  test('world canvas constraints work through rotated nested parents', () {
    final original = hall();
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    final group = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      x: 50,
      y: 250,
      rotation: 90,
    );
    final nested = original.copyWith(
      nodes: [
        group,
        ...original.nodes.map(
          (n) =>
              n.id == table.id ? n.copyWith(parentId: group.id, x: 0, y: 0) : n,
        ),
      ],
    );
    final result = reflowTablesAtCanvasEdges(nested, {table.id});
    expect(
      result.nodes
          .where((n) => n.kind == 'seat')
          .every((n) => inside(result, n)),
      isTrue,
    );
    expect(layoutCollisions(result), isEmpty);
    expect(validateDocument(result), isEmpty);
  });

  test('returning to open space restores the gesture baseline placements', () {
    final baseline = hall();
    final table = baseline.nodes.firstWhere((n) => n.kind == 'table');
    final edge = reflowTablesAtCanvasEdges(baseline, {table.id});
    expect(edge.toJson(), isNot(baseline.toJson()));
    final middle = transformNodes(baseline, {table.id}, dy: 150);
    final result = reflowTablesAtCanvasEdges(middle, {table.id});
    expect(result.toJson(), middle.toJson());
  });

  test(
    'manual chair inside stays exact when other chairs need wall reflow',
    () {
      final original = hall();
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final seat = original.nodes.firstWhere(
        (n) => n.kind == 'seat' && n.y > 0,
      );
      final before = original.copyWith(
        nodes: original.nodes
            .map(
              (n) => n.id == seat.id
                  ? n.copyWith(properties: {...n.properties, 'manual': true})
                  : n,
            )
            .toList(),
      );
      final result = reflowTablesAtCanvasEdges(before, {table.id});
      expect(
        result.nodes.firstWhere((n) => n.id == seat.id).toJson(),
        before.nodes.firstWhere((n) => n.id == seat.id).toJson(),
      );
      expect(result.nodes.every((n) => inside(result, n)), isTrue);
    },
  );
}
