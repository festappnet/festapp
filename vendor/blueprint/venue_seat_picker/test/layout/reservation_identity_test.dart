import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'protected standalone seat cannot acquire a new atomic unit through apply or history',
    () {
      final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200),
          b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 260, y: 200);
      final document = VenueLayoutDocument(nodes: [a, b]);
      final grouped = document.copyWith(
        selectionUnits: [
          {
            'id': newLayoutId(),
            'kind': 'atomic',
            'nodeIds': [a.id, b.id],
          },
        ],
      );
      var protected = <String>{a.id};
      final c = VenueLayoutController(
        document,
        protectedSeatIds: () => protected,
      );
      expect(c.apply(grouped), isFalse);
      expect(c.document, same(document));
      expect(
        c.error,
        'Reserved or blocked seats prevent changing this seat group.',
      );
      protected = {};
      expect(c.apply(grouped), isTrue);
      c.undo();
      protected = {a.id};
      c.redo();
      expect(c.document, same(document));
      expect(
        c.error,
        'Reserved or blocked seats prevent changing this seat group.',
      );
      c.dispose();
    },
  );
  test(
    'protected standalone seat cannot join a previously free existing unit',
    () {
      final seats = [
        for (var i = 0; i < 3; i++)
          LayoutNode(id: newLayoutId(), kind: 'seat', x: 200 + i * 60, y: 200),
      ];
      final unit = {
        'id': newLayoutId(),
        'kind': 'atomic',
        'nodeIds': [seats[1].id, seats[2].id],
      };
      final document = VenueLayoutDocument(
        nodes: seats,
        selectionUnits: [unit],
      );
      final c = VenueLayoutController(
        document,
        protectedSeatIds: () => {seats.first.id},
      );
      expect(
        c.apply(
          document.copyWith(
            selectionUnits: [
              {...unit, 'nodeIds': seats.map((s) => s.id).toList()},
            ],
          ),
        ),
        isFalse,
      );
      expect(c.document, same(document));
      c.dispose();
    },
  );

  test(
    'protected standalone seat cannot be replaced by another node kind with same UUID',
    () {
      final seat = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200);
      final document = VenueLayoutDocument(nodes: [seat]);
      final controller = VenueLayoutController(
        document,
        protectedSeatIds: () => {seat.id},
      );
      final changed = document.copyWith(
        nodes: [LayoutNode(id: seat.id, kind: 'shape', x: seat.x, y: seat.y)],
      );
      expect(
        validateDocument(changed),
        isEmpty,
        reason:
            'The generic geometry is valid; live reservation protection must reject it.',
      );
      expect(controller.apply(changed), isFalse);
      expect(controller.document, same(document));
      expect(controller.canUndo, isFalse);
      expect(
        controller.error,
        'Reserved or blocked seats prevent shrinking this table.',
      );
      controller.protectedSeatIds = () => {};
      expect(controller.apply(changed), isTrue);
      controller.dispose();
    },
  );
  test(
    'canonical unit membership remains protected through apply and history',
    () {
      final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200),
          b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 260, y: 200);
      final document = VenueLayoutDocument(
        nodes: [a, b],
        selectionUnits: [
          {
            'id': newLayoutId(),
            'kind': 'atomic',
            'nodeIds': [a.id, b.id],
          },
        ],
      );
      final reduced = document.copyWith(
        selectionUnits: [
          {
            ...document.selectionUnits.single,
            'nodeIds': [a.id],
          },
        ],
      );
      var protected = <String>{a.id};
      final c = VenueLayoutController(
        document,
        protectedSeatIds: () => protected,
      );
      addTearDown(c.dispose);
      expect(c.apply(reduced), isFalse);
      expect(c.document, same(document));
      protected = {};
      expect(c.apply(reduced), isTrue);
      protected = {a.id};
      c.undo();
      expect(c.document, same(reduced));
      protected = {};
      c.undo();
      expect(c.document, same(document));
      protected = {a.id};
      c.redo();
      expect(c.document, same(document));
    },
  );
}
