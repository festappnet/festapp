import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

bool fits(VenueLayoutDocument d, LayoutNode n) {
  final b = nodeBounds(d, n), c = d.canvas;
  return b['x']! >= (c['x'] as num) - .001 &&
      b['y']! >= (c['y'] as num) - .001 &&
      b['x']! + b['width']! <= (c['x'] as num) + (c['width'] as num) + .001 &&
      b['y']! + b['height']! <= (c['y'] as num) + (c['height'] as num) + .001;
}

void main() {
  test(
    'manual chair snaps near a free standard slot without changing bindings',
    () {
      final original = tableLayout(shape: 'rect', count: 4),
          seat = original.nodes.firstWhere((n) => n.kind == 'seat'),
          d = original.copyWith(
            nodes: original.nodes
                .map(
                  (n) => n.id == seat.id
                      ? n.copyWith(
                          x: n.x + 10,
                          y: n.y + 6,
                          properties: n.properties,
                        )
                      : n,
                )
                .toList(),
          ),
          result = snapAttachedChairPosition(d, seat.id),
          snapped = result.nodes.firstWhere((n) => n.id == seat.id);
      expect(snapped.x, seat.x);
      expect(snapped.y, seat.y);
      expect(snapped.id, seat.id);
      expect(snapped.parentId, seat.parentId);
      expect(seatAttachment(result, snapped.id)!['placement']['mode'], 'free');
      final attachment = result.attachments.firstWhere(
        (a) => a['seatId'] == seat.id,
      );
      expect(attachment['placement']['mode'], 'free');
      expect(
        attachment.keys.toSet(),
        containsAll(['seatId', 'targetId', 'placement', 'rotationMode']),
      );
      expect(layoutCollisions(result), isEmpty);
      expect(validateDocument(result), isEmpty);
    },
  );

  test(
    'far chair does not teleport and occupied or outside slots do not attract',
    () {
      final original = tableLayout(shape: 'rect', count: 4),
          seats = original.nodes.where((n) => n.kind == 'seat').toList(),
          seat = seats.first,
          other = seats[2];
      VenueLayoutDocument moved(double x, double y) => original.copyWith(
        nodes: original.nodes
            .map((n) => n.id == seat.id ? n.copyWith(x: x, y: y) : n)
            .toList(),
      );
      final far = moved(600, 600);
      expect(snapAttachedChairPosition(far, seat.id), same(far));
      final occupied = moved(other.x, other.y);
      expect(snapAttachedChairPosition(occupied, seat.id), same(occupied));
      final near = moved(seat.x + 10, seat.y + 6);
      expect(
        snapAttachedChairPosition(near, seat.id, tolerance: 1),
        same(near),
      );
      expect(
        () => snapAttachedChairPosition(near, seat.id, tolerance: double.nan),
        throwsArgumentError,
      );
    },
  );
}
