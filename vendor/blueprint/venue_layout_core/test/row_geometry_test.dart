import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument legacy(VenueLayoutDocument generated) => generated.copyWith(
  nodes: generated.nodes.map((n) {
    if (n.kind == 'group') {
      final properties = {...n.properties}
        ..remove('arc')
        ..remove('spacing')
        ..remove('rowSpacing')
        ..remove('aisle');
      return n.copyWith(properties: properties);
    }
    final i = int.parse('${n.properties['slot']}'.split(':').last);
    final root = generated.nodes.first;
    final half = ((root.properties['seatsPerRow'] as num) - 1) / 2;
    return n.copyWith(
      rotation:
          atan(2 * (root.properties['arc'] as num) * (i - half)) * 180 / pi,
    );
  }).toList(),
);

void main() {
  test('arc chair angle follows the curve tangent in world distance units', () {
    for (final spacing in [40.0, 80.0]) {
      final d = rowLayout(
        rows: 2,
        seatsPerRow: 5,
        blocks: 2,
        spacing: spacing,
        rowSpacing: 90,
        aisle: 120,
        arc: 8,
      );
      final seats = d.nodes.where((n) => n.kind == 'seat').toList();
      expect(seats.length, 20);
      for (final seat in seats) {
        final i = int.parse('${seat.properties['slot']}'.split(':').last);
        expect(
          seat.rotation,
          closeTo(atan(16 * (i - 2) / spacing) * 180 / pi, 1e-10),
        );
      }
      // The symmetric secant is exactly the derivative of this parabola.
      final left = seats[0], middle = seats[1], right = seats[2];
      expect(
        tan(middle.rotation * pi / 180),
        closeTo((right.y - left.y) / (right.x - left.x), 1e-10),
      );
      expect(validateDocument(d), isEmpty);
    }
  });

  test(
    'straight rows retain zero angles and persist every generator parameter',
    () {
      final d = rowLayout(
        rows: 3,
        seatsPerRow: 4,
        blocks: 2,
        spacing: 70,
        rowSpacing: 95,
        aisle: 0,
      );
      expect(
        d.nodes.where((n) => n.kind == 'seat').every((n) => n.rotation == 0),
        isTrue,
      );
      expect(rowLayoutParameters(d, d.nodes.first.id), {
        'rows': 3,
        'seatsPerRow': 4,
        'blocks': 2,
        'spacing': 70,
        'rowSpacing': 95,
        'aisle': 0,
        'arc': 0,
      });
      expect(
        validateDocument(VenueLayoutDocument.fromJson(d.toJson())),
        isEmpty,
      );
    },
  );

  test(
    'reconciling dimensions retains chair IDs and new generator settings',
    () {
      final before = rowLayout(
        rows: 2,
        seatsPerRow: 3,
        blocks: 2,
        spacing: 60,
        rowSpacing: 70,
        aisle: 85,
        arc: 4,
      );
      final root = before.nodes.first;
      final after = reconcileAssembly(
        before,
        root.id,
        rowLayout(
          rows: 3,
          seatsPerRow: 4,
          blocks: 2,
          spacing: 72,
          rowSpacing: 96,
          aisle: 110,
          arc: 6,
        ),
      );
      final slots = {
        for (final seat in after.nodes.where((n) => n.kind == 'seat'))
          seat.properties['slot']: seat,
      };
      for (final seat in before.nodes.where((n) => n.kind == 'seat')) {
        expect(slots[seat.properties['slot']]!.id, seat.id);
      }
      expect(rowLayoutParameters(after, root.id), {
        'rows': 3,
        'seatsPerRow': 4,
        'blocks': 2,
        'spacing': 72,
        'rowSpacing': 96,
        'aisle': 110,
        'arc': 6,
      });
      expect(validateDocument(after), isEmpty);
    },
  );

  test(
    'invalid row geometry fails before creating invalid chair transforms',
    () {
      for (final invalid in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => rowLayout(spacing: invalid), throwsArgumentError);
        expect(() => rowLayout(rowSpacing: invalid), throwsArgumentError);
      }
      for (final invalid in [double.nan, double.infinity]) {
        expect(() => rowLayout(arc: invalid), throwsArgumentError);
      }
      expect(() => rowLayout(aisle: -1), throwsArgumentError);
      expect(() => rowLayout(aisle: double.nan), throwsArgumentError);
    },
  );
}
