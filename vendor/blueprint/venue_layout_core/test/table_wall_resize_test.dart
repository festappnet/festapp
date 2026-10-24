import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final (dx, dy, handle) in [
    (-500.0, -500.0, 'se'),
    (500.0, -500.0, 'sw'),
    (-500.0, 500.0, 'ne'),
    (500.0, 500.0, 'nw'),
  ]) {
    test('$handle resize at a corner keeps feasible perimeter seating', () {
      final original =
          tableLayout(
            shape: 'rect',
            count: 6,
            width: 190,
            height: 110,
            x: 250,
            y: 200,
          ).copyWith(
            canvas: {
              'x': 0,
              'y': 0,
              'width': 500,
              'height': 400,
              'fill': '#FFFFFFFF',
            },
          );
      final id = original.nodes.firstWhere((n) => n.kind == 'table').id;
      // A persisted layout can already have shifted rows against the walls.
      // Build that arrangement directly, independently of drag clamping policy.
      final positions = [
        [-75.0, 87.0],
        [-23.0, 87.0],
        [29.0, 87.0],
        [81.0, 87.0],
        [127.0, -35.0],
        [127.0, 17.0],
      ];
      var seatIndex = 0;
      final before = original.copyWith(
        nodes: [
          for (final node in original.nodes)
            if (node.id == id)
              node.copyWith(x: dx < 0 ? 95 : 405, y: dy < 0 ? 55 : 345)
            else
              node.copyWith(
                x: positions[seatIndex][0] * (dx < 0 ? 1 : -1),
                y: positions[seatIndex++][1] * (dy < 0 ? 1 : -1),
                rotation: node.rotation,
              ),
        ],
      );
      expect(layoutCollisions(before), isEmpty);
      final beforeTable = before.nodes.firstWhere((n) => n.id == id);
      expect(
        beforeTable.x + (dx < 0 ? -1 : 1) * beforeTable.width / 2,
        closeTo(dx < 0 ? 0 : 500, .002),
      );
      expect(
        beforeTable.y + (dy < 0 ? -1 : 1) * beforeTable.height / 2,
        closeTo(dy < 0 ? 0 : 400, .002),
      );
      final sx = handle.contains('w') ? -1 : 1;
      final sy = handle.contains('n') ? -1 : 1;
      final after = resizeNode(
        before,
        id,
        192,
        112,
        handle: handle,
        protectedSeatIds: before.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet(),
      );
      final table = after.nodes.firstWhere((n) => n.id == id);
      expect(table.width, 192);
      expect(table.height, 112);
      expect(
        table.x - sx * table.width / 2,
        closeTo(beforeTable.x - sx * beforeTable.width / 2, .002),
      );
      expect(
        table.y - sy * table.height / 2,
        closeTo(beforeTable.y - sy * beforeTable.height / 2, .002),
      );
      expect(
        after.nodes.map((n) => n.id).toSet(),
        before.nodes.map((n) => n.id).toSet(),
      );
      expect(layoutCollisions(after), isEmpty);
      expect(validateDocument(after), isEmpty);
      for (final node in after.nodes) {
        final bounds = nodeBounds(after, node);
        expect(bounds['x'], greaterThanOrEqualTo(-.001));
        expect(bounds['y'], greaterThanOrEqualTo(-.001));
        expect(bounds['x']! + bounds['width']!, lessThanOrEqualTo(500.001));
        expect(bounds['y']! + bounds['height']!, lessThanOrEqualTo(400.001));
      }
      expect(after.canvas, before.canvas);
    });
  }
}
