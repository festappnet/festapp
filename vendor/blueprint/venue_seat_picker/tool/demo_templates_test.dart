import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'all package templates validate with fresh identities and exact capacity',
    () {
      expect(VenueLayoutTemplates.all.length, 15);
      for (final template in VenueLayoutTemplates.all) {
        final a = template.create(), b = template.create();
        expect(validateDocument(a), isEmpty, reason: template.id);
        if (template.id == 'cinema-galaxy') {
          final chairs = a.nodes
              .where((n) => n.kind == 'seat' && n.parentId == null)
              .toList();
          expect(chairs, hasLength(76));
          for (final chair in chairs) {
            expect(chair.properties['shape'], 'polygon');
            final points = chair.properties['points'] as List;
            expect(points.take(2), [
              [-40.0, -40.0],
              [40.0, -40.0],
            ]);
            expect(
              points.where((p) => (p[1] as num) > 16),
              hasLength(greaterThan(10)),
            );
            expect(points.last[0], closeTo(-40, .001));
          }
          expect(a.nodes.where((n) => isCouchNode(n)), hasLength(4));
          expect(
            a.nodes.where(isCouchNode).every((n) => n.rotation == 180),
            isTrue,
          );
          expect(
            a.nodes.any((n) => n.properties['text'] == 'Entrance'),
            isFalse,
          );
          expect(
            a.nodes.where((n) => n.properties['shape'] == 'polyline'),
            isEmpty,
          );
        }
        expect(a.schemaVersion, 2, reason: template.id);
        expect(
          a.nodes.every(
            (node) =>
                !node.properties.keys.any(legacyStyleDestinations.containsKey),
          ),
          isTrue,
          reason: template.id,
        );
        expect(
          a.nodes.where((n) => n.kind == 'seat').length,
          template.seatCount,
          reason: template.id,
        );
        expect(
          a.nodes
              .where((n) => n.kind == 'capacityArea')
              .fold<int>(
                0,
                (sum, n) => sum + (n.properties['capacity'] as int),
              ),
          template.standingCapacity,
        );
        expect(
          a.nodes
              .map((n) => n.id)
              .toSet()
              .intersection(b.nodes.map((n) => n.id).toSet()),
          isEmpty,
        );
        expect(jsonEncode(a.toJson()), isNot(contains('price')));
        final clone = cloneLayout(a);
        expect(
          validateDocument(clone),
          isEmpty,
          reason: 'clone ${template.id}',
        );
        expect(
          clone.nodes
              .map((n) => n.id)
              .toSet()
              .intersection(a.nodes.map((n) => n.id).toSet()),
          isEmpty,
        );
      }
    },
  );
}
