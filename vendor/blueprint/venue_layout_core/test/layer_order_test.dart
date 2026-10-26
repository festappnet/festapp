import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

final resources = Map<String, dynamic>.from(
  jsonDecode(
    File('../../assets/layout_fonts/fixtures.json').readAsStringSync(),
  ),
);
List<String> paintedNodes(VenueLayoutDocument d) => [
  for (final item in compileScene(d, resources: resources)['items'] as List)
    (item['nodeId'] ?? item['id']) as String,
];
void main() {
  test(
    'subtrees paint atomically and hit testing reverses actual paint order',
    () {
      final back = LayoutNode(id: newLayoutId(), kind: 'group'),
          front = LayoutNode(id: newLayoutId(), kind: 'group', z: 1),
          caption = LayoutNode(
            id: newLayoutId(),
            kind: 'text',
            parentId: back.id,
            x: 100,
            y: 100,
            properties: {'text': 'A'},
            style: {
              'label': {'fontFamilyId': canonicalLabelDefaults['fontFamilyId']},
            },
          ),
          body = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            parentId: back.id,
            x: 100,
            y: 100,
          ),
          cover = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            parentId: front.id,
            x: 100,
            y: 100,
          ),
          d = VenueLayoutDocument(nodes: [front, body, caption, cover, back]);
      expect(validateDocument(d), isEmpty);
      expect(orderedNodes(d).map((n) => n.id), [
        back.id,
        body.id,
        caption.id,
        front.id,
        cover.id,
      ]);
      expect(paintedNodes(d), [body.id, caption.id, cover.id]);
      expect(hitTest(d, 100, 100), cover.id);
      final moved = moveLayoutLayers(d, {back.id}, toFront: true);
      expect(paintedNodes(moved), [cover.id, body.id, caption.id]);
      expect(hitTest(moved, 100, 100), caption.id);
      expect(nodeBounds(moved, caption), nodeBounds(d, caption));
      expect(
        moved.nodes.map((n) => n.id).toSet(),
        d.nodes.map((n) => n.id).toSet(),
      );
      expect(hitTest(d, 100, 100), cover.id);
      expect(
        paintedNodes(moveLayoutLayers(moved, {back.id}, toFront: false)),
        paintedNodes(d),
      );
      final roundtrip = VenueLayoutDocument.fromJson(
        jsonDecode(jsonEncode(moved.toJson())),
      );
      expect(
        compileScene(roundtrip, resources: resources),
        compileScene(moved, resources: resources),
      );
      expect(
        compileSceneNodes(moved, {
          caption.id,
          cover.id,
          body.id,
        }, resources: resources)['items'],
        compileScene(moved, resources: resources)['items'],
      );
    },
  );
  test('node labels stay with their body and z overrides all kind bands', () {
    final table = LayoutNode(
          surface: const {'type': 'rect'},
          id: newLayoutId(),
          kind: 'table',
          z: 1,
          x: 100,
          y: 100,
          label: 'A',
          properties: {},
          style: {
            'label': {'fontFamilyId': canonicalLabelDefaults['fontFamilyId']},
          },
        ),
        shape = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 100,
          y: 100,
          label: 'A',
          properties: {},
          style: {
            'label': {'fontFamilyId': canonicalLabelDefaults['fontFamilyId']},
          },
        ),
        d = VenueLayoutDocument(nodes: [shape, table]);
    expect(paintedNodes(d), [shape.id, shape.id, table.id, table.id]);
    final moved = reorderLayoutLayers(d, {shape.id}, direction: 1);
    expect(paintedNodes(moved), [table.id, table.id, shape.id, shape.id]);
    expect(hitTest(moved, 100, 100), shape.id);
    expect(
      identical(moveLayoutLayers(moved, {shape.id}, toFront: true), moved),
      isTrue,
    );
  });
  test(
    'nested reordering preserves hierarchy and blocks locked assemblies',
    () {
      final group = LayoutNode(id: newLayoutId(), kind: 'group'),
          a = LayoutNode(id: newLayoutId(), kind: 'shape', parentId: group.id),
          b = LayoutNode(id: newLayoutId(), kind: 'text', parentId: group.id),
          other = LayoutNode(id: newLayoutId(), kind: 'shape', z: 1),
          d = VenueLayoutDocument(nodes: [group, a, b, other]);
      final moved = moveLayoutLayers(d, {group.id, b.id}, toFront: true);
      expect(orderedNodes(moved).map((n) => n.id), [
        other.id,
        group.id,
        a.id,
        b.id,
      ]);
      expect(moved.nodes.firstWhere((n) => n.id == b.id).z, b.z);
      final nested = moveLayoutLayers(d, {a.id}, toFront: true);
      expect(orderedNodes(nested).map((n) => n.id), [
        group.id,
        b.id,
        a.id,
        other.id,
      ]);
      for (final lockedId in [group.id, a.id]) {
        final locked = d.copyWith(
          nodes: [
            for (final n in d.nodes)
              n.id == lockedId ? n.copyWith(locked: true) : n,
          ],
        );
        expect(
          () => moveLayoutLayers(locked, {group.id}, toFront: true),
          throwsStateError,
        );
        expect(
          () => reorderLayoutLayers(locked, {a.id}, direction: 1),
          throwsStateError,
        );
      }
      expect(
        () => moveLayoutLayers(d, {'missing'}, toFront: true),
        throwsArgumentError,
      );
      expect(
        () => reorderLayoutLayers(d, {a.id}, direction: 0),
        throwsArgumentError,
      );
    },
  );
  test('front and back preserve locked siblings and roundtrip order', () {
    final a = LayoutNode(id: newLayoutId(), kind: 'shape', z: 0),
        locked = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          z: 1,
          locked: true,
        ),
        b = LayoutNode(id: newLayoutId(), kind: 'shape', z: 2),
        d = VenueLayoutDocument(nodes: [a, locked, b]);
    final front = moveLayoutLayers(d, {a.id}, toFront: true);
    expect(
      front.nodes.firstWhere((n) => n.id == locked.id).toJson(),
      locked.toJson(),
    );
    expect(orderedNodes(front).map((n) => n.id), [locked.id, b.id, a.id]);
    final step = reorderNodes(d, {a.id}, 1);
    expect(orderedNodes(step).map((n) => n.id), [locked.id, a.id, b.id]);
    expect(
      step.nodes
          .firstWhere((n) => n.id == locked.id)
          .copyWith(z: locked.z)
          .toJson(),
      locked.toJson(),
    );
    final roundtrip = VenueLayoutDocument.fromJson(
      jsonDecode(jsonEncode(step.toJson())),
    );
    expect(
      orderedNodes(roundtrip).map((n) => n.id),
      orderedNodes(step).map((n) => n.id),
    );
  });
}
