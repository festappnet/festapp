import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  test(
    'source table gains full-size chairs from plus and palette with original spacing',
    () {
      final original = VenueLayoutTemplates.create('scout-ball-182');
      final table = original.nodes.firstWhere(
        (n) => n.kind == 'table' && n.label == '21',
      );
      final old = original.nodes
          .where((n) => n.parentId == table.id && n.kind == 'seat')
          .toList();
      final increased = reflowTable(
        original,
        table.id,
        old.length + 1,
        constrainToCanvas: true,
      );
      final added = increased.nodes.singleWhere(
        (n) =>
            n.parentId == table.id &&
            n.kind == 'seat' &&
            !old.any((o) => o.id == n.id),
      );
      expect(added.width, 77.5);
      expect(added.height, 77.5);
      expect(
        TableSeating.fromDocument(
          increased,
          increased.nodes.firstWhere((n) => n.id == table.id),
        ).gap,
        11.25,
      );
      expect(layoutCollisions(increased), isEmpty);
      final loose = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        width: 40,
        height: 40,
        x: 1300,
        y: 1300,
      );
      final attached = attachSeat(
        original.copyWith(nodes: [...original.nodes, loose]),
        loose.id,
        table.id,
      );
      final chair = attached.nodes.singleWhere((n) => n.id == loose.id);
      expect(chair.width, 77.5);
      expect(chair.height, 77.5);
      expect(layoutCollisions(attached), isEmpty);
      expect(documentSeating(original).width, 77.5);
      expect(
        VenueLayoutDocument.fromJson(attached.toJson()).toJson(),
        attached.toJson(),
      );
    },
  );
  test(
    'chair gap configuration reflows without replacing identities and is undoable',
    () {
      final source = tableLayout(
        shape: 'rect',
        x: 600,
        y: 600,
        width: 300,
        height: 180,
        count: 6,
      );
      final table = source.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(source);
      addTearDown(c.dispose);
      final originalIds = source.nodes.map((n) => n.id).toSet();
      c.setTableSeating(
        table.id,
        const TableSeating(width: 60, height: 60, gap: 24, spacing: 16),
      );
      expect(c.error, isNull);
      expect(c.document.nodes.map((n) => n.id).toSet(), originalIds);
      for (final n in c.document.nodes.where((n) => n.kind == 'seat')) {
        expect(n.width, 60);
        expect(n.height, 60);
      }
      expect(
        TableSeating.fromDocument(
          c.document,
          c.document.nodes.firstWhere((n) => n.id == table.id),
        ).gap,
        24,
      );
      expect(layoutCollisions(c.document), isEmpty);
      c.undo();
      expect(c.document.toJson(), source.toJson());
      expect(
        () => configureTableSeating(
          source,
          table.id,
          const TableSeating(width: 500, height: 500),
        ),
        throwsArgumentError,
      );
    },
  );
}
