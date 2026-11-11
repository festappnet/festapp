import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final kind in ['table', 'seat', 'furniture', 'obstacle', 'decoration']) {
    test('round table translation respects $kind at an attached chair', () {
      final base = tableLayout(
        shape: 'ellipse',
        x: 500,
        y: 500,
        width: 200,
        height: 200,
      );
      final table = base.nodes.firstWhere((n) => n.kind == 'table');
      final chair = base.nodes.firstWhere((n) => n.kind == 'seat');
      final chairWorld = worldMatrices(base)[chair.id]!;
      final obstacle = LayoutNode(
        id: newLayoutId(),
        kind: kind == 'obstacle' || kind == 'decoration' ? 'shape' : kind,
        x: chairWorld[4] + 400,
        y: chairWorld[5],
        width: chair.width,
        height: chair.height,
        surface: kind == 'table' ? const {'type': 'rect'} : null,
        properties: kind == 'obstacle' ? const {'obstacle': true} : const {},
      );
      final document = base.copyWith(nodes: [...base.nodes, obstacle]);
      final moved = translateLayoutWithinCanvas(document, {table.id}, dx: 400);
      if (kind == 'decoration') {
        expect(moved.nodes.firstWhere((n) => n.id == table.id).x, 900);
        expect(
          moved.nodes.firstWhere((n) => n.id == chair.id).toJson(),
          chair.toJson(),
        );
      } else {
        expect(moved, same(document));
      }
    });
  }

  test('round tabletop body cannot move through a small obstacle', () {
    final base = tableLayout(
      shape: 'ellipse',
      x: 500,
      y: 500,
      width: 200,
      height: 200,
    );
    final table = base.nodes.firstWhere((n) => n.kind == 'table');
    final document = base.copyWith(
      nodes: [
        ...base.nodes,
        LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          x: 900,
          y: 500,
          width: 10,
          height: 10,
        ),
      ],
    );
    expect(
      translateLayoutWithinCanvas(document, {table.id}, dx: 400),
      same(document),
    );
  });

  test('placement cache does not retain obstacles from another snapshot', () {
    final base = tableLayout(shape: 'ellipse', x: 500, y: 500, width: 200);
    final table = base.nodes.firstWhere((n) => n.kind == 'table');
    final blocked = base.copyWith(
      nodes: [
        ...base.nodes,
        LayoutNode(id: newLayoutId(), kind: 'seat', x: 900, y: 500),
      ],
    );
    expect(
      translateLayoutWithinCanvas(blocked, {table.id}, dx: 400),
      same(blocked),
    );
    final clear = blocked.copyWith(nodes: base.nodes);
    expect(
      translateLayoutWithinCanvas(clear, {
        table.id,
      }, dx: 400).nodes.firstWhere((n) => n.id == table.id).x,
      900,
    );
    expect(
      translateLayoutWithinCanvas(blocked, {table.id}, dx: 400),
      same(blocked),
    );
  });

  test('oversized physical obstacles remain in placement queries', () {
    final base = tableLayout(shape: 'ellipse', x: 500, y: 500, width: 200);
    final table = base.nodes.firstWhere((n) => n.kind == 'table');
    final document = base.copyWith(
      nodes: [
        ...base.nodes,
        LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 900,
          y: 500,
          width: 10000,
          height: 10000,
          properties: const {'obstacle': true},
        ),
      ],
    );
    expect(
      translateLayoutWithinCanvas(document, {table.id}, dx: 400),
      same(document),
    );
  });
}
