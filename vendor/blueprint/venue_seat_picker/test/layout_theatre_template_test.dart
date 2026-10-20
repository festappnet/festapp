import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_layout_templates.dart';

void main() {
  test(
    'theatre stalls balcony and boxes face the stage with editable row geometry',
    () {
      final document = VenueLayoutTemplates.create('theatre');
      expect(validateDocument(document), isEmpty);
      final seats = document.nodes.where((n) => n.kind == 'seat').toList();
      expect(seats, hasLength(188));
      final matrices = worldMatrices(document);
      for (final seat in seats) {
        final m = matrices[seat.id]!;
        // The backrest is local +Y, so the front is transformed local -Y.
        final forwardX = -m[2], forwardY = -m[3];
        expect(
          forwardY,
          lessThan(0),
          reason: 'Front must point toward the stage above the audience',
        );
        expect(
          forwardX * (900 - m[4]),
          greaterThan(0),
          reason:
              'Side seats must face inward toward the stage, including boxes',
        );
      }
      final curved = document.nodes.where(
        (n) =>
            n.assembly?['kind'] == 'rows' &&
            (n.assembly?['arc'] as num? ?? 0) != 0,
      );
      expect(curved, hasLength(2));
      for (final row in curved) {
        expect(rowLayoutParameters(document, row.id)['arc'], lessThan(0));
      }
      expect(layoutCollisions(document), isEmpty);
    },
  );
}
