import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:fstapp/components/blueprint/blueprint_table_seating.dart';

void main() {
  test('custom grid table supports adding and snapping chairs', () {
    var document = tableLayout(
      shape: 'rect',
      count: 6,
      width: 500,
      height: 360,
      x: 700,
      y: 700,
    );
    final id = document.nodes.first.id;
    document = setTableSurfaceKind(document, id, 'grid');
    final controller = VenueLayoutController(document);
    addTearDown(controller.dispose);
    controller.setSeatCount(id, 7);
    expect(controller.error, isNull);
    expect(
      controller.document.nodes.where((n) => n.kind == 'seat'),
      hasLength(7),
    );
    expect(
      () => reflowTablesAtCanvasEdges(controller.document, {id}),
      returnsNormally,
    );
    final seat = controller.document.nodes.firstWhere((n) => n.kind == 'seat');
    expect(
      () => snapAttachedChairPosition(controller.document, seat.id),
      returnsNormally,
    );
  });
  test('imported manual chairs allow a ninth chair at the free table end', () {
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 100,
      y: 200,
      width: 190.52,
      height: 76.207,
      surface: {'type': 'rect'},
      seating: {'width': 37.2, 'height': 37.2, 'gap': 15.296},
    );
    final chairs = [
      for (var i = 0; i < 8; i++)
        LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          parentId: table.id,
          x: (i % 4 - 1.5) * 47.63,
          y: i < 4 ? -72 : 72,
          width: 37.2,
          height: 37.2,
        ),
    ];
    final original = VenueLayoutDocument(
      nodes: [table, ...chairs],
      attachments: [
        for (final chair in chairs)
          {
            'id': newLayoutId(),
            'seatId': chair.id,
            'targetId': table.id,
            'placement': {'mode': 'free'},
            'rotationMode': 'auto',
          },
      ],
    );
    expect(
      tableCapacity(table),
      8,
      reason: 'inherited padding caused the disabled plus',
    );
    expect(() => reflowTable(original, table.id, 9), throwsArgumentError);
    final normalized = normalizeBlueprintTableSeating(original);
    expect(tableCapacity(normalized.nodes.first), 10);
    final c = VenueLayoutController(
      normalized,
      protectedSeatIds: () => chairs.map((n) => n.id).toSet(),
    );
    addTearDown(c.dispose);
    c.setSeatCount(table.id, 9);
    expect(c.error, isNull);
    expect(c.document.nodes.where((n) => n.kind == 'seat').length, 9);
    for (final chair in chairs) {
      expect(
        c.document.nodes.singleWhere((n) => n.id == chair.id).toJson(),
        chair.toJson(),
      );
    }
    expect(c.placementIssues, isEmpty);
    c.undo();
    expect(c.document.toJson(), normalized.toJson());
    expect(
      normalizeBlueprintTableSeating(normalized).toJson(),
      normalized.toJson(),
    );
  });
}
