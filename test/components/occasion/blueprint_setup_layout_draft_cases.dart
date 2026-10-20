import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/occasion/setup/blueprint_setup_layout_draft.dart';

void main() {
  test(
      'setup draft keeps explicit overrides and never persists live identities/resources',
      () {
    const group = '00000000-0000-4000-8000-000000000001';
    const seat = '00000000-0000-4000-8000-000000000002';
    const area = '00000000-0000-4000-8000-000000000003';
    final document = VenueLayoutDocument(nodes: [
      LayoutNode(id: group, kind: 'group'),
      LayoutNode(id: seat, kind: 'seat', parentId: group, label: 'Chair'),
      LayoutNode(id: area, kind: 'capacityArea', x: 300, y: 300),
    ]);
    final draft = BlueprintSetupLayoutDraft.empty(
            document: document, resources: {'fonts': {}})
        .reconcile(document, defaultProductId: 42)
        .withArea(nodeId: area, productId: 43, capacity: 5);
    expect(
        resolveNodeAppearance(draft.document,
                document.nodes.firstWhere((node) => node.id == seat))
            .label['fontFamilyId'],
        canonicalLabelDefaults['fontFamilyId']);
    expect(draft.seatBindings[seat]!.productId, 42);
    expect(draft.groupProducts[group], 42);
    final encoded = draft.toJson();
    expect(encoded.containsKey('resources'), false);
    final binding = (encoded['seatBindings'] as List).single as Map;
    expect(binding.containsKey('spotId'), false);
    binding['productId'] = 44;
    final restored = BlueprintSetupLayoutDraft.fromJson(encoded)
        .reconcile(draft.document, defaultProductId: 99);
    expect(restored.seatBindings[seat]!.productId, 44);
    expect(restored.areaBindings.single['capacity'], 5);
    expect(() => restored.withArea(nodeId: area, productId: 43, capacity: -1),
        throwsStateError);
  });
  test('new setup seat in mixed group needs an explicit group default', () {
    const group = '00000000-0000-4000-8000-000000000001';
    const first = '00000000-0000-4000-8000-000000000002';
    const second = '00000000-0000-4000-8000-000000000003';
    const added = '00000000-0000-4000-8000-000000000004';
    final document = VenueLayoutDocument(nodes: [
      LayoutNode(id: group, kind: 'group'),
      LayoutNode(id: first, kind: 'seat', parentId: group),
      LayoutNode(id: second, kind: 'seat', parentId: group)
    ]);
    final draft = BlueprintSetupLayoutDraft.fromJson({
      'layout': document.toJson(),
      'seatBindings': [
        for (final id in [first, second])
          {
            'nodeId': id,
            'groupNodeId': group,
            'productId': id == first ? 42 : 43,
            'title': '',
            'blocked': false
          }
      ],
      'groupProducts': [],
      'areaBindings': []
    });
    final next = VenueLayoutDocument.fromJson({
      ...document.toJson(),
      'nodes': [
        ...document.nodes.map((node) => node.toJson()),
        LayoutNode(id: added, kind: 'seat', parentId: group).toJson()
      ]
    });
    final updated = draft.reconcile(next, defaultProductId: 99);
    expect(updated.seatBindings[first]!.productId, 42);
    expect(updated.seatBindings[added]!.productId, isNull);
    expect(updated.groupProducts.containsKey(group), false);
    final chosen = updated.withGroupProduct(group, 99, assignNodeIds: {added});
    expect(chosen.seatBindings[added]!.productId, 99);
    expect(chosen.seatBindings[first]!.productId, 42);
    expect(chosen.groupProducts[group], 99);
  });

  test(
      'setup native table children inherit ancestor business default and preserve overrides',
      () {
    const group = '00000000-0000-4000-8000-000000000001';
    const table = '00000000-0000-4000-8000-000000000002';
    const seat = '00000000-0000-4000-8000-000000000003';
    const added = '00000000-0000-4000-8000-000000000004';
    final document = VenueLayoutDocument(nodes: [
      LayoutNode(id: group, kind: 'group'),
      LayoutNode(
          id: table, kind: 'table', surface: {'type': 'rect'}, parentId: group),
      LayoutNode(id: seat, kind: 'seat', parentId: table)
    ]);
    final draft = BlueprintSetupLayoutDraft.fromJson({
      'layout': document.toJson(),
      'seatBindings': [
        {
          'nodeId': seat,
          'groupNodeId': group,
          'productId': 99,
          'title': 'Override',
          'blocked': false
        }
      ],
      'groupProducts': [
        {'groupNodeId': group, 'productId': 42}
      ],
      'areaBindings': []
    });
    final next = document.copyWith(nodes: [
      ...document.nodes,
      LayoutNode(id: added, kind: 'seat', parentId: table)
    ]);
    final updated = draft.reconcile(next, defaultProductId: 7);
    expect(updated.seatBindings[added]!.groupNodeId, group);
    expect(updated.seatBindings[added]!.productId, 42);
    expect(updated.seatBindings[seat]!.productId, 99);
  });
}
