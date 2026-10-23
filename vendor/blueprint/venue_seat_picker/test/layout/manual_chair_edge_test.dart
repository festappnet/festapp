import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'rigid table movement preserves the free chair pose while clamping at the wall',
    () {
      final original = tableLayout(shape: 'roundedRect', count: 6);
      final c = VenueLayoutController(original);
      addTearDown(c.dispose);
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final chairs = original.nodes.where((n) => n.kind == 'seat').toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      final chair = chairs.first;
      c.select({chair.id});
      c.moveSelection(-10, 0);
      expect(
        seatPlacementFree(
          c.document,
          c.document.nodes.firstWhere((n) => n.id == chair.id),
        ),
        true,
      );
      final manuallyPositioned = c.document;
      c.select({table.id});
      c.moveSelection(-2000, 0);
      expect(
        selectionBounds(c.document, {table.id})['x'],
        closeTo(0, .02),
        reason: 'The complete rigid assembly clamps at the canvas boundary.',
      );
      expect(
        c.document.nodes.map((n) => n.id).toSet(),
        original.nodes.map((n) => n.id).toSet(),
      );
      expect(
        c.placementIssues.where(
          (i) => i.code == 'outside_canvas' || i.code == 'overlap',
        ),
        isEmpty,
      );
      expect(c.document.canvas, original.canvas);
      expect(c.document.attachments, hasLength(6));
      c.undo();
      expect(c.document.toJson(), manuallyPositioned.toJson());
    },
  );
}
