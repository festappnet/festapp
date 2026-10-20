import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'banquet has a distinct chair silhouette and shares geometry with partial rendering and hit testing',
    () {
      final source = tableLayout(shape: 'rect', count: 6, x: 400, y: 400);
      final doc = withLayoutMaterialFamily(source, 'banquet');
      expect(validateDocument(doc), isEmpty);
      final seat = doc.nodes.firstWhere((n) => n.kind == 'seat');
      final scene = compileScene(doc)['items'] as List;
      final body = scene.firstWhere((i) => i['id'] == seat.id);
      final lounge =
          (compileScene(withLayoutMaterialFamily(source, 'lounge'))['items']
                  as List)
              .firstWhere((i) => i['id'] == seat.id);
      expect(body['path'], isNot(lounge['path']));
      expect((body['path'] as List).where((p) => p[0] == 'M'), hasLength(4));
      expect(
        (body['path'] as List).where((p) => p[0] == 'L').length,
        lessThan(32),
      );
      expect(
        scene.where((i) => i['nodeId'] == seat.id && i['kind'] == 'decoration'),
        hasLength(1),
      );
      expect(
        compileSceneNodes(doc, {seat.id})['items'],
        scene
            .where((i) => i['nodeId'] == seat.id || i['id'] == seat.id)
            .toList(),
      );
      final m = worldMatrix(doc, seat);
      expect(hitTest(doc, m[4], m[5]), seat.id);
      expect(VenueLayoutDocument.fromJson(doc.toJson()).toJson(), doc.toJson());
      expect(
        doc.nodes.map((n) => n.toJson()),
        source.nodes.map((n) => n.toJson()),
      );
      final occupied =
          (compileScene(
                    doc,
                    presentation: {
                      seat.id: {'status': 'occupied'},
                    },
                  )['items']
                  as List)
              .firstWhere((i) => i['id'] == seat.id);
      expect(occupied['fill'], '#94A3B8FF');
    },
  );
}
