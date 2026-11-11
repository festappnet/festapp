import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final (kind, properties, physical) in [
    ('seat', <String, dynamic>{}, true),
    ('table', <String, dynamic>{}, true),
    ('furniture', <String, dynamic>{}, true),
    ('shape', <String, dynamic>{'obstacle': true}, true),
    ('shape', <String, dynamic>{'role': 'obstacle'}, true),
    ('shape', <String, dynamic>{}, false),
    ('text', <String, dynamic>{'text': 'Dance floor'}, false),
    ('capacityArea', <String, dynamic>{'capacity': 30}, false),
    ('group', <String, dynamic>{}, false),
  ]) {
    test('$kind $properties shares the physical collision policy', () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: kind,
        x: -50,
        y: -50,
        width: 40,
        height: 40,
        properties: properties,
        surface: kind == 'table' ? const {'type': 'rect'} : null,
      );
      final blocker = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: -50,
        y: -50,
        width: 20,
        height: 20,
      );
      final document = VenueLayoutDocument(nodes: [node, blocker]);
      final index = collisionIndexFor(document);
      expect(isLayoutObstacle(node), physical);
      expect(
        index
            .query({'x': -55, 'y': -55, 'width': 10, 'height': 10})
            .contains(node.id),
        physical,
      );
      expect(
        layoutCollisions(document),
        physical ? contains(unorderedEquals([node.id, blocker.id])) : isEmpty,
      );
    });
  }

  test(
    'nested assemblies use physical children without colliding with parents',
    () {
      final couch = couchLayout(x: 500, y: 500);
      final parent = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: -800,
        y: -700,
        rotation: 30,
      );
      final root = couch.nodes.first;
      final document = couch.copyWith(
        nodes: [
          parent,
          for (final node in couch.nodes)
            node.id == root.id ? node.copyWith(parentId: parent.id) : node,
        ],
      );
      final index = collisionIndexFor(document);
      expect(
        index.hullFor(root.id),
        worldHull(root, worldMatrices(document)[root.id]!),
      );
      expect(layoutCollisions(document), isEmpty);
      for (final node in couch.nodes) {
        final hull = index.hullFor(node.id);
        expect(index.query(boundsOfPoints(hull)), contains(node.id));
      }
    },
  );

  test('published hulls cannot corrupt a cached document index', () {
    final document = tableLayout(shape: 'ellipse', x: 500, y: 500);
    final id = document.nodes.first.id;
    final index = collisionIndexFor(document);
    final hull = index.hullFor(id);
    expect(collisionIndexFor(document), same(index));
    expect(index.hullFor(id), same(hull));
    expect(() => hull.clear(), throwsUnsupportedError);
    expect(() => hull.first[0] = 0, throwsUnsupportedError);
    final next = transformNodes(document, {id}, dx: 100);
    expect(collisionIndexFor(next), isNot(same(index)));
    expect(
      collisionIndexFor(next).hullFor(id).first[0],
      closeTo(hull.first[0] + 100, .001),
    );
  });
}
