import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'seat hover adds an outline without changing availability or selection',
    () {
      final seat = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
      final doc = VenueLayoutDocument(nodes: [seat]);
      final scene = compileScene(
        doc,
        presentation: {
          seat.id: {'highlighted': true},
        },
      );
      final items = scene['items'] as List;
      expect(
        items.where((item) => item['id'] == '${seat.id}:highlight').length,
        1,
      );
      expect(
        items.singleWhere((item) => item['id'] == seat.id)['selected'],
        false,
      );
    },
  );
  test(
    'resize snaps only dragged edges and ignores its fixed opposite edge',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 200,
        y: 200,
        width: 100,
        height: 100,
        surface: {'type': 'rect'},
      );
      final neighbor = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 354,
        y: 200,
        width: 100,
        height: 100,
        surface: {'type': 'rect'},
      );
      final doc = VenueLayoutDocument(nodes: [node, neighbor]);
      final snap = snapResize(doc, node, 153, 100, sx: 1, sy: 0);
      expect(snap.width, 154);
      expect(snap.height, 100);
      expect(snap.guides.every((g) => g['axis'] == 'x'), isTrue);
      expect(
        snapResize(doc, node, 153, 100, sx: 1, sy: 0, disabled: true).width,
        153,
      );
      expect(
        snapResize(doc, node, 153, 100, sx: 1, sy: 0, zoom: 20).width,
        153,
      );
    },
  );
  test(
    'resize uses actual row bounds rather than the group placeholder size',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        x: 200,
        y: 200,
        width: 1,
        height: 1,
      );
      final doc = VenueLayoutDocument(nodes: [node]);
      expect(
        snapResize(
          doc,
          node,
          153,
          40,
          sx: 1,
          sy: 0,
          grid: 8,
          localBounds: {'x': -50, 'y': -20, 'width': 100, 'height': 40},
        ).width,
        154,
      );
    },
  );
  test('resize grid snapping follows rotated object axes', () {
    final node = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: 200,
      y: 200,
      width: 100,
      height: 100,
      rotation: 90,
      surface: {'type': 'rect'},
    );
    final doc = VenueLayoutDocument(nodes: [node]);
    expect(snapResize(doc, node, 153, 100, sx: 1, sy: 0, grid: 8).width, 154);
  });
}
