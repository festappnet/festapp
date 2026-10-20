import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'new bars are editable seatless surfaces; legacy explicit stools remain readable',
    () {
      final d = barLayout();
      expect(d.nodes.length, 1);
      expect(isBarNode(d.nodes.single), true);
      expect(d.nodes.single.surface!['type'], 'rect');
      expect(validateDocument(d), isEmpty);
      expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
      expect(
        barLayout(count: 4).nodes.where((n) => n.kind == 'seat').length,
        4,
      );
    },
  );
  test(
    'centerline sketch builds an actual concave U surface, not a bounding rectangle',
    () {
      final node = sketchSurface(
        [
          [200, 500],
          [200, 200],
          [600, 200],
          [600, 500],
        ],
        breadth: 80,
        bar: true,
      );
      final d = VenueLayoutDocument(nodes: [node]);
      expect(validateDocument(d), isEmpty);
      expect(hitTest(d, 200, 400), node.id);
      expect(hitTest(d, 400, 200), node.id);
      expect(hitTest(d, 400, 400), isNull);
      expect(
        () => sketchSurface([
          [0, 0],
          [100, 0],
          [0, 0],
        ]),
        throwsStateError,
      );
    },
  );

  test(
    'surface edits never remove protected reservations or change immutable input',
    () {
      var d = tableLayout(shape: 'rect', count: 6, width: 500, height: 360);
      d = setTableSurfaceKind(d, d.nodes.first.id, 'grid');
      final before = d.toJson(), id = d.nodes.first.id;
      final reserved = d.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      expect(
        () => resizeNode(d,id,20,20*d.nodes.firstWhere((n)=>n.id==id).height/d.nodes.firstWhere((n)=>n.id==id).width,protectedSeatIds:reserved),
        throwsA(isA<TableResizeRejected>()),
      );
      expect(d.toJson(), before);
    },
  );
  test(
    'transport material has a different silhouette and preserves selection states',
    () {
      final d = withLayoutMaterialFamily(busLayout(rows: 2), 'transit');
      expect(validateDocument(d), isEmpty);
      final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
      final scene = compileScene(
        d,
        presentation: {
          seat.id: {'selected': true},
        },
      );
      final item = (scene['items'] as List).firstWhere(
        (i) => i['id'] == seat.id,
      );
      expect(item['fill'], '#267329FF');
      expect(
        (scene['items'] as List).any((i) => i['id'] == '${seat.id}:seat-style'),
        true,
      );
      expect(
        d.nodes.where(
          (n) => '${n.properties['slot']}'.contains('travel-direction'),
        ),
        isNotEmpty,
      );
    },
  );
}
