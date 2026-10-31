import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final surface in ['grid', 'circle', 'rect']) {
    test('chair snapping uses the $surface surface after serialization', () {
      var document = tableLayout(
        shape: 'rect',
        count: 6,
        width: 500,
        height: 360,
        x: 700,
        y: 700,
      );
      final tableId = document.nodes.first.id;
      document = setTableSurfaceKind(document, tableId, surface);
      document = VenueLayoutDocument.fromJson(document.toJson());
      final seat = document.nodes.firstWhere((n) => n.kind == 'seat');
      final before = document.toJson();
      final snapped = snapAttachedChairPosition(
        document,
        seat.id,
        tolerance: 1000,
      );
      expect(validateDocument(snapped), isEmpty);
      expect(snapped.nodes.map((n) => n.id), document.nodes.map((n) => n.id));
      expect(document.toJson(), before);
      // A generated chair already occupies a valid perimeter anchor.
      final after = snapped.nodes.firstWhere((n) => n.id == seat.id);
      expect(after.x, closeTo(seat.x, .01));
      expect(after.y, closeTo(seat.y, .01));
      expect(after.rotation, closeTo(seat.rotation, .01));
    });
  }
}
