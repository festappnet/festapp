import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'V1 selection grows green marker and centers a white check without changing physical hit geometry',
    () {
      final seat = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        width: 77.5,
        height: 77.5,
        rotation: 180,
        properties: {},
        x: 100,
        y: 100,
        style: {'cornerRadius': 20},
      );
      final doc = VenueLayoutDocument(nodes: [seat]);
      final plain = (compileScene(doc)['items'] as List).singleWhere(
        (i) => i['id'] == seat.id,
      );
      final presentation = {
        seat.id: {'selected': true, 'pending': true},
      };
      final items =
          compileScene(doc, presentation: presentation)['items'] as List;
      final body = items.singleWhere((i) => i['id'] == seat.id),
          mark = items.singleWhere((i) => i['id'] == '${seat.id}:state');
      expect(body['fill'], '#267329FF');
      expect(body['hitPath'], plain['hitPath']);
      expect(body['bounds']['width'], greaterThan(plain['bounds']['width']));
      expect(mark['stroke'], '#FFFFFFFF');
      expect(mark['matrix'], [1, 0, 0, 1, 100, 100]);
      expect((body['path'][0][1] as num) + 48, closeTo(20, .001));
      expect(mark['path'], hasLength(3));
      expect(mark['bounds']['x'], lessThan(100));
      expect(mark['bounds']['x'] + mark['bounds']['width'], greaterThan(100));
      expect(
        compileSceneNodes(doc, {seat.id}, presentation: presentation)['items'],
        items,
      );
    },
  );
  test(
    'minimal defaults and material family are explicit and preserve authored geometry',
    () {
      final empty = withLayoutMinimalStyle(VenueLayoutDocument.empty());
      expect(empty.styles['kinds']['seat']['fill'], '#267329FF');
      expect(empty.styles['kinds']['table']['material'], 'minimal');
      expect(empty.canvas['floorStyle'], 'plain');
      final source = tableLayout(shape: 'rect');
      final family = withLayoutMinimalStyle(source);
      expect(validateDocument(family), isEmpty);
      expect(
        family.nodes.map((n) => n.toJson()),
        source.nodes.map((n) => n.toJson()),
      );
      expect(layoutMaterialFamilies['minimal']!['construction'], 'simple');
    },
  );
}
