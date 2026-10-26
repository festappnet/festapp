import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument plan({int count = 6}) {
  final d = tableLayout(shape: 'rect', count: count, width: 300, height: 200);
  return d.copyWith(
    canvas: {...d.canvas, 'width': 2400, 'height': 1800},
    nodes: [
      for (final n in d.nodes)
        n.kind == 'table' ? n.copyWith(x: 800, y: 700) : n,
    ],
  );
}

List<double> opposite(VenueLayoutDocument d, String id, String handle) {
  final n = d.nodes.firstWhere((n) => n.id == id);
  final points = <String, List<double>>{
    'n': [0, n.height / 2],
    'ne': [-n.width / 2, n.height / 2],
    'e': [-n.width / 2, 0],
    'se': [-n.width / 2, -n.height / 2],
    's': [0, -n.height / 2],
    'sw': [n.width / 2, -n.height / 2],
    'w': [n.width / 2, 0],
    'nw': [n.width / 2, n.height / 2],
  };
  final p = points[handle]!;
  return transformPoint(worldMatrices(d)[id]!, p[0], p[1]);
}

void main() {
  for (final handle in ['n', 'ne', 'e', 'se', 's', 'sw', 'w', 'nw']) {
    test(
      '$handle resize retains opposite world anchor under parent rotation',
      () {
        var d = plan();
        final table = d.nodes.firstWhere((n) => n.kind == 'table');
        final parent = LayoutNode(
          id: newLayoutId(),
          kind: 'group',
          x: 100,
          y: 80,
          rotation: 31,
          width: 1,
          height: 1,
        );
        d = d.copyWith(
          nodes: [
            parent,
            for (final n in d.nodes)
              n.id == table.id
                  ? n.copyWith(parentId: parent.id, rotation: 17)
                  : n,
          ],
        );
        final before = opposite(d, table.id, handle);
        final ids = d.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet();
        final next = resizeNode(d, table.id, 360, 240, handle: handle);
        final after = opposite(next, table.id, handle);
        expect(after[0], closeTo(before[0], .02));
        expect(after[1], closeTo(before[1], .02));
        expect(
          next.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
          ids,
        );
        expect(validateDocument(next), isEmpty);
      },
    );
  }
  test('growth clips at canvas without moving the opposite anchor', () {
    var d = plan(count: 0);
    final id = d.nodes.single.id;
    d = d.copyWith(
      canvas: {...d.canvas, 'width': 1000, 'height': 1000},
      nodes: [d.nodes.single.copyWith(x: 400, y: 400)],
    );
    final before = opposite(d, id, 'e');
    final next = resizeNode(d, id, 5000, 200, handle: 'e');
    final table = next.nodes.single;
    expect(opposite(next, id, 'e')[0], closeTo(before[0], .01));
    expect(table.width, lessThanOrEqualTo(750));
    expect(
      worldHull(
        table,
        worldMatrices(next)[id]!,
      ).every((p) => p[0] >= 0 && p[0] <= 1000 && p[1] >= 0 && p[1] <= 1000),
      isTrue,
    );
  });
  test('surface reshape returns free seats to automatic placement', () {
    var d = plan();
    final table = d.nodes.firstWhere((n) => n.kind == 'table');
    final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
    d = transformNodes(d, {seat.id}, dx: 20, dy: 10);
    expect(seatAttachment(d, seat.id)!['placement']['mode'], 'free');
    final ids = d.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet();
    final next = resizeNode(d, table.id, 400, 260, handle: 'e');
    expect(
      next.attachments.every(
        (a) =>
            a['placement']['mode'] == 'automatic' &&
            a['rotationMode'] == 'auto',
      ),
      isTrue,
    );
    expect(
      next.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
      ids,
    );
    expect(validateDocument(next), isEmpty);
  });
  test('protected shrink and locked descendants reject atomically', () {
    final d = plan();
    final table = d.nodes.firstWhere((n) => n.kind == 'table');
    final ids = d.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet();
    final before = d.toJson();
    expect(
      () => resizeNode(d, table.id, 40, 30, handle: 'e', protectedSeatIds: ids),
      throwsA(isA<TableResizeRejected>()),
    );
    expect(d.toJson(), before);
    final locked = d.copyWith(
      nodes: [
        for (final n in d.nodes)
          n.id == ids.first ? n.copyWith(locked: true) : n,
      ],
    );
    expect(
      () => resizeNode(locked, table.id, 400, 260, handle: 'e'),
      throwsStateError,
    );
  });
  test('settled handle input returns the same document', () {
    final d = plan();
    final t = d.nodes.firstWhere((n) => n.kind == 'table');
    expect(
      identical(resizeNode(d, t.id, t.width, t.height, handle: 'se'), d),
      isTrue,
    );
  });
}
