import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_layout_templates.dart';
import 'package:venue_seat_picker/src/templates/scout_reference_data.dart';

void main() {
  test(
    'scout reference retains every original seat coordinate, label and table membership',
    () {
      final doc = VenueLayoutTemplates.create('scout-ball-182');
      expect(validateDocument(doc), isEmpty);
      final seats = {
        for (final n in doc.nodes.where((n) => n.kind == 'seat')) n.label: n,
      };
      final nodes = {for (final n in doc.nodes) n.id: n};
      expect(seats, hasLength(182));
      final counts = <String, int>{};
      for (final original in scoutSeats) {
        final seat = seats[original.$2]!,
            m = worldMatrix(doc, seats[original.$2]!);
        expect(
          m[4],
          closeTo((original.$3 + .5) * 100, .001),
          reason: original.$2,
        );
        expect(
          m[5],
          closeTo((original.$4 + .5) * 100, .001),
          reason: original.$2,
        );
        final table = nodes[seat.parentId]!;
        expect(table.label, '${original.$1}');
        counts.update(table.label, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(counts, {
        for (var i = 1; i <= 31; i++) '$i': i == 18 || i == 19 ? 4 : 6,
      });
      expect(doc.attachments, hasLength(182));
      expect(layoutCollisions(doc), isEmpty);
      expect(VenueLayoutDocument.fromJson(doc.toJson()).toJson(), doc.toJson());
      expect(
        doc.nodes.where((n) => n.properties['role'] == 'obstacle'),
        hasLength(2),
      );
      expect(
        doc.nodes.where((n) => n.kind == 'text').map((n) => n.label),
        containsAll(['Pódium', 'Taneční parket', 'vstup']),
      );
    },
  );
  test(
    'scout table footprints match reviewed raster edges and each creation has fresh IDs',
    () {
      final doc = VenueLayoutTemplates.create('scout-ball-182');
      final tables = {
        for (final n in doc.nodes.where((n) => n.kind == 'table')) n.label: n,
      };
      expect(tables, hasLength(31));
      for (final r in scoutTables) {
        final b = nodeBounds(doc, tables['${r.$1}']!);
        expect(b['x'], closeTo(r.$2, .001));
        expect(b['y'], closeTo(r.$3, .001));
        expect(b['width'], closeTo(r.$4 - r.$2, .001));
        expect(b['height'], closeTo(r.$5 - r.$3, .001));
      }
      expect(tables['18']!.y, lessThan(tables['19']!.y));
      final other = VenueLayoutTemplates.create('scout-ball-182');
      expect(
        doc.nodes
            .map((n) => n.id)
            .toSet()
            .intersection(other.nodes.map((n) => n.id).toSet()),
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
        withLayoutMaterialFamily(doc, 'lounge').nodes.map((n) => n.toJson()),
        doc.nodes.map((n) => n.toJson()),
      );
    },
  );
}
