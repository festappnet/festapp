import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_layout_templates.dart';
import 'package:venue_seat_picker/src/templates/scout_balcony_reference_data.dart';

void main() {
  test(
    'balcony reference preserves 249 identities, labels, positions and memberships',
    () {
      final doc = VenueLayoutTemplates.create('scout-ball-balcony-249');
      expect(validateDocument(doc), isEmpty);
      final seats = {
        for (final n in doc.nodes.where((n) => n.kind == 'seat')) n.label: n,
      };
      final nodes = {for (final n in doc.nodes) n.id: n};
      expect(seats, hasLength(249));
      for (final s in scoutBalconySeats) {
        final seat = seats[s.$2]!, m = worldMatrix(doc, seats[s.$2]!);
        expect(m[4], closeTo((s.$3 + .5) * 100, .001), reason: s.$2);
        expect(m[5], closeTo((s.$4 + .5) * 100, .001), reason: s.$2);
        expect(nodes[seat.parentId]!.label, s.$1 == 22 ? '22' : 'Stůl ${s.$1}');
        expect(seat.properties['state'], isNull);
      }
      expect(doc.nodes.where((n) => n.kind == 'table'), hasLength(21));
      expect(doc.attachments, hasLength(234));
      expect(doc.sections.map((s) => s['title']), ['Sál', 'Balkón']);
      expect(
        doc.nodes.where((n) => n.kind == 'text').map((n) => n.label),
        containsAll(['Pódium', 'Bar', 'Vstup', 'Balkón', 'Schodiště']),
      );
      expect(layoutCollisions(doc), isEmpty);
      expect(VenueLayoutDocument.fromJson(doc.toJson()).toJson(), doc.toJson());
      final other = VenueLayoutTemplates.create('scout-ball-balcony-249');
      expect(
        nodes.keys.toSet().intersection(other.nodes.map((n) => n.id).toSet()),
        isEmpty,
      );
      expect(doc.styles['kinds']['table']['material'], 'simple');
      expect(doc.styles['kinds']['seat']['seatStyle'], 'plain');
      expect(doc.styles['kinds']['seat']['fill'], '#267329FF');
      expect(doc.canvas['floorStyle'], 'plain');
      expect(
        doc.nodes
            .where((n) => n.kind == 'seat')
            .every((n) => n.width == 77.5 && n.height == 77.5),
        isTrue,
      );
      final items = compileScene(doc)['items'] as List;
      expect(
        items.where(
          (item) =>
              '${item['id']}'.endsWith(':seat-style') ||
              '${item['id']}'.endsWith(':table-style'),
        ),
        isEmpty,
      );

      expect(
        withLayoutMaterialFamily(doc, 'hall').nodes.map((n) => n.toJson()),
        doc.nodes.map((n) => n.toJson()),
      );
    },
  );
  test(
    'original SVG table footprints and vertical orientation survive import',
    () {
      final doc = VenueLayoutTemplates.create('scout-ball-balcony-249');
      for (final r in scoutBalconyTables) {
        final table = doc.nodes.firstWhere(
          (n) => n.kind == 'table' && n.label == 'Stůl ${r.$1}',
        );
        final b = nodeBounds(doc, table);
        expect(b['x'], closeTo(r.$2, .001));
        expect(b['y'], closeTo(r.$3, .001));
        expect(b['width'], closeTo(r.$4 - r.$2, .001));
        expect(b['height'], closeTo(r.$5 - r.$3, .001));
        expect(table.rotation, r.$1 >= 16 ? 270 : 0);
      }
    },
  );
}
