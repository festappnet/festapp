import 'dart:convert';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'automatic banquet sides and a single head survive editing and import',
    () {
      final d = tableLayout(
        shape: 'roundedRect',
        width: 64,
        height: 420,
        count: 15,
        seating: const TableSeating(
          width: 40,
          height: 40,
          gap: 4,
          spacing: 16,
          edgePadding: 0,
        ),
        edgeCounts: [0, 7, 1, 7],
      );
      final table = d.nodes.firstWhere((n) => n.kind == 'table');
      expect(tableEdgeCapacities(table), [1, 7, 1, 7]);
      expect(
        d.nodes.where(
          (n) => n.kind == 'seat' && tableSideForSeat(d, n) == 'bottom',
        ),
        hasLength(1),
      );
      expect(
        d.nodes.where(
          (n) => n.kind == 'seat' && tableSideForSeat(d, n) == 'top',
        ),
        isEmpty,
      );
      expect(
        d.nodes
            .where((n) => n.kind == 'seat')
            .every((n) => n.properties['manual'] != true),
        true,
      );
      expect(d.attachments.every((a) => a['manual'] != true), true);
      expect(layoutCollisions(d), isEmpty);
      final imported = VenueLayoutDocument.fromJson(
        jsonDecode(jsonEncode(d.toJson())),
      );
      expect(validateDocument(imported), isEmpty);
      expect(sameLayoutDocument(d, imported), true);
      final ids = d.nodes.map((n) => n.id).toSet();
      final resized = resizeNode(imported, table.id, 96, 476);
      expect(
        resized.nodes.firstWhere((n) => n.id == table.id).seating['edgeCounts'],
        [0, 7, 1, 7],
      );
      expect(resized.nodes.map((n) => n.id).toSet(), ids);
      expect(layoutCollisions(resized), isEmpty);

      final grown = reflowTable(imported, table.id, 16);
      expect(
        grown.nodes.firstWhere((n) => n.id == table.id).seating['edgeCounts'],
        [1, 7, 1, 7],
      );
      expect(grown.nodes.map((n) => n.id).toSet().containsAll(ids), true);
      final restored = reflowTable(
        grown,
        table.id,
        15,
        edgeCounts: [0, 7, 1, 7],
      );
      expect(
        restored.nodes.where(
          (n) => n.kind == 'seat' && tableSideForSeat(d, n) == 'bottom',
        ),
        hasLength(1),
      );
      expect(
        restored.nodes.where(
          (n) => n.kind == 'seat' && tableSideForSeat(d, n) == 'top',
        ),
        isEmpty,
      );
    },
  );
  test(
    'edge settings reject invalid requests without changing the document',
    () {
      final d = tableLayout(shape: 'rect', count: 6, width: 240, height: 120);
      final table = d.nodes.firstWhere((n) => n.kind == 'table'),
          before = d.toJson();
      for (final counts in [
        [1, 2],
        [1, -1, 5, 1],
        [1, 1, 1, 1],
        [0, 6, 0, 0],
      ]) {
        expect(
          () => reflowTable(d, table.id, 6, edgeCounts: counts),
          throwsArgumentError,
        );
      }
      expect(d.toJson(), before);
      final bad = table.copyWith(
        seating: {
          ...table.seating,
          'edgeCounts': [1, -1, 3, 3],
        },
      );
      expect(
        validateDocument(
          d.copyWith(
            nodes: [for (final n in d.nodes) n.id == table.id ? bad : n],
          ),
        ),
        isNotEmpty,
      );
    },
  );
}
