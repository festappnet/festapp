import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

(VenueLayoutDocument, String, String) fixture({bool locked = false}) {
  final original = tableLayout(shape: 'rect', count: 6),
      target = original.nodes.firstWhere((n) => n.kind == 'table'),
      fixed = original.nodes.firstWhere((n) => n.kind == 'seat'),
      free = LayoutNode(id: newLayoutId(), kind: 'seat', x: 750, y: 300);
  return (
    original.copyWith(
      nodes: [
        ...original.nodes.map(
          (n) => n.id == fixed.id
              ? n.copyWith(x: 0, locked: locked, properties: n.properties)
              : n,
        ),
        free,
      ],
      attachments: original.attachments
          .map(
            (a) => a['seatId'] == fixed.id
                ? {
                    ...a,
                    'id': newLayoutId(),
                    'placement': {'mode': 'free'},
                  }
                : a,
          )
          .toList(),
    ),
    target.id,
    free.id,
  );
}

void main() {
  test(
    'attached chair reserves manual footprint instead of overlapping it',
    () {
      final (before, tableId, seatId) = fixture();
      final fixed = before.nodes.firstWhere(
            (n) => n.kind == 'seat' && seatPlacementFree(before, n),
          ),
          fixedAttachment = before.attachments.firstWhere(
            (a) => a['seatId'] == fixed.id,
          ),
          after = attachSeat(before, seatId, tableId);
      expect(canAttachSeatToTable(before, seatId, tableId), isTrue);
      expect(
        after.nodes.map((n) => n.id).toSet(),
        before.nodes.map((n) => n.id).toSet(),
      );
      expect(
        after.nodes.firstWhere((n) => n.id == fixed.id).toJson(),
        fixed.toJson(),
      );
      expect(
        after.attachments.firstWhere((a) => a['seatId'] == fixed.id),
        fixedAttachment,
      );
      expect(after.nodes.firstWhere((n) => n.id == seatId).parentId, tableId);
      expect(after.nodes.where((n) => n.parentId == tableId).length, 7);
      expect(layoutCollisions(after), isEmpty);
      expect(validateDocument(after), isEmpty);
      expect(after.canvas, before.canvas);
    },
  );

  test(
    'locked attached chair stays unchanged while another chair attaches',
    () {
      final (before, tableId, seatId) = fixture(locked: true);
      final fixed = before.nodes.firstWhere((n) => n.locked),
          after = attachSeat(before, seatId, tableId);
      expect(
        after.nodes.firstWhere((n) => n.id == fixed.id).toJson(),
        fixed.toJson(),
      );
      expect(layoutCollisions(after), isEmpty);
      expect(canAttachSeatToTable(before, seatId, tableId), isTrue);
    },
  );

  test(
    'unplaceable attachment rejects atomically and hover uses same decision',
    () {
      final (original, tableId, seatId) = fixture();
      final fixed = original.nodes.firstWhere(
            (n) => n.kind == 'seat' && seatPlacementFree(original, n),
          ),
          before = original.copyWith(
            nodes: original.nodes
                .map(
                  (n) => n.id == fixed.id
                      ? n.copyWith(width: 1000, height: 1000)
                      : n,
                )
                .toList(),
          ),
          snapshot = before.toJson();
      expect(canAttachSeatToTable(before, seatId, tableId), isFalse);
      expect(() => attachSeat(before, seatId, tableId), throwsStateError);
      expect(before.toJson(), snapshot);
      expect(before.nodes.firstWhere((n) => n.id == seatId).parentId, isNull);
    },
  );

  test(
    'attachment uses in-canvas slots and does not ban other table overlap',
    () {
      final original = tableLayout(shape: 'rect', count: 3, x: 250, y: 50),
          target = original.nodes.firstWhere((n) => n.kind == 'table'),
          free = LayoutNode(id: newLayoutId(), kind: 'seat', x: 750, y: 300),
          other = LayoutNode(
            surface: const {'type': 'rect'},
            id: newLayoutId(),
            kind: 'table',
            x: 250,
            y: 50,
            width: 180,
            height: 100,
          ),
          before = original.copyWith(nodes: [...original.nodes, free, other]),
          result = attachSeat(before, free.id, target.id);
      for (final seat in result.nodes.where((n) => n.parentId == target.id)) {
        expect(nodeBounds(result, seat)['y'], greaterThanOrEqualTo(-.001));
      }
      expect(canAttachSeatToTable(before, free.id, target.id), isTrue);
      expect(layoutCollisions(result), isNotEmpty);
      expect(result.canvas, before.canvas);
    },
  );

  test('moving between tables retains chair and attachment identities', () {
    final source = tableLayout(shape: 'rect', count: 3),
        sourceSeat = source.nodes.firstWhere((n) => n.kind == 'seat'),
        target = LayoutNode(
          surface: const {'type': 'rect'},
          id: newLayoutId(),
          kind: 'table',
          x: 900,
          y: 400,
          width: 180,
          height: 100,
        ),
        attachmentId = newLayoutId(),
        before = source.copyWith(
          nodes: [...source.nodes, target],
          attachments: source.attachments
              .map(
                (a) => a['seatId'] == sourceSeat.id
                    ? {...a, 'id': attachmentId}
                    : a,
              )
              .toList(),
        ),
        result = attachSeat(before, sourceSeat.id, target.id);
    expect(
      result.nodes.firstWhere((n) => n.id == sourceSeat.id).parentId,
      target.id,
    );
    final attached = result.attachments.firstWhere(
      (a) => a['seatId'] == sourceSeat.id,
    );
    expect(attached['id'], attachmentId);
    expect(attached['targetId'], target.id);
    expect(
      result.nodes.map((n) => n.id).toSet(),
      before.nodes.map((n) => n.id).toSet(),
    );
    expect(validateDocument(result), isEmpty);
    expect(attachSeat(result, sourceSeat.id, target.id), same(result));
  });

  test(
    'generic reflow stays usable outside canvas and rejects locked targets',
    () {
      final d = tableLayout(shape: 'ellipse', count: 4, x: -100, y: -200);
      expect(d.nodes.where((n) => n.kind == 'seat').length, 4);
      final (before, tableId, seatId) = fixture();
      final locked = before.copyWith(
        nodes: before.nodes
            .map((n) => n.id == tableId ? n.copyWith(locked: true) : n)
            .toList(),
      );
      expect(canAttachSeatToTable(locked, seatId, tableId), isFalse);
      expect(() => attachSeat(locked, seatId, tableId), throwsStateError);
    },
  );

  test('incoming chair adopts the table seating size without overlap', () {
    final (original, tableId, seatId) = fixture();
    final before = original.copyWith(
      nodes: original.nodes
          .map((n) => n.id == seatId ? n.copyWith(width: 200, height: 200) : n)
          .toList(),
    );
    expect(canAttachSeatToTable(before, seatId, tableId), isTrue);
    final attached = attachSeat(before, seatId, tableId);
    final seat = attached.nodes.firstWhere((n) => n.id == seatId);
    expect(seat.width, 40);
    expect(seat.height, 40);
    expect(layoutCollisions(attached), isEmpty);
    expect(before.nodes.firstWhere((n) => n.id == seatId).parentId, isNull);
  });
}
