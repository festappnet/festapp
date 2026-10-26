import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('generated cushion state colors override stored upholstery', () {
    final document = couchLayout();
    final seat = document.nodes.firstWhere((node) => node.kind == 'seat');
    expect(seat.style['fill'], '#F8FAFCFF');
    dynamic fill(Map<String, dynamic> state) {
      final items =
          compileScene(document, presentation: {seat.id: state})['items']
              as List;
      return items.singleWhere((item) => item['id'] == seat.id)['fill'];
    }

    expect(fill({}), '#F8FAFCFF');
    expect(fill({'selected': true}), '#267329FF');
    expect(fill({'status': 'occupied'}), '#94A3B8FF');
    expect(
      fill({'selected': true, 'status': 'occupied', 'fill': '#123456FF'}),
      '#123456FF',
    );
  });

  test(
    'couch scene has backrest arms and seat cushions without visible labels',
    () {
      final couch = LayoutNode(
        id: newLayoutId(),
        kind: 'furniture',
        x: 200,
        y: 200,
        width: 160,
        height: 80,
        label: 'Gauč 7',
        properties: {'furniture': 'couch', 'shape': 'roundedRect'},
      );
      final seats = [
        for (final x in [-35.0, 35.0])
          LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            parentId: couch.id,
            x: x,
            width: 40,
            height: 40,
            label: 'Seat',
          ),
      ];
      final document = VenueLayoutDocument.empty().copyWith(
        nodes: [couch, ...seats],
        selectionUnits: [
          {
            'id': newLayoutId(),
            'kind': 'atomic',
            'nodeIds': seats.map((s) => s.id).toList(),
            'label': 'Gauč 7',
          },
        ],
      );
      final items = compileScene(document)['items'] as List;
      final body = items.singleWhere((i) => i['id'] == couch.id) as Map;
      expect(body['label'], 'Gauč 7');
      expect(body['hitPath'], isNotEmpty);
      for (final part in ['backrest', 'left-arm', 'right-arm']) {
        final item =
            items.singleWhere((i) => i['id'] == '${couch.id}:$part') as Map;
        expect(item['nodeId'], couch.id);
        expect(item['path'], isNotEmpty);
        expect(item['paintOrder'], isNotNull);
        expect(item.containsKey('hitPath'), isFalse);
      }
      for (final seat in seats) {
        final item = items.singleWhere((i) => i['id'] == seat.id) as Map;
        expect(
          item['fill'],
          resolveNodeAppearance(document, seat).values['fill'],
        );
        expect(item['hitPath'], isNotEmpty);
      }
      expect(items.where((i) => i['kind'] == 'glyphs'), isEmpty);
      expect(document.nodes.first.label, 'Gauč 7');
      final selected =
          compileScene(
                document,
                presentation: {
                  seats.first.id: {'selected': true},
                },
              )['items']
              as List;
      expect(
        selected.singleWhere((i) => i['id'] == seats.first.id)['fill'],
        '#267329FF',
      );
    },
  );

  test(
    'rectangular table aliases share rounded corners and respect explicit zero',
    () {
      final table = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        width: 160,
        height: 80,
      );
      final rounded = nodePath(
        table.copyWith(properties: {'shape': 'roundedRect'}),
      );
      for (final shape in ['rect', 'rectangle']) {
        expect(nodePath(table.copyWith(properties: {'shape': shape})), rounded);
        expect(
          nodePath(
            table.copyWith(properties: {'shape': shape, 'cornerRadius': 0}),
          ).where((p) => p.first == 'Q'),
          isEmpty,
        );
      }
      final plain = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        properties: {'shape': 'rectangle'},
      );
      expect(nodePath(plain).where((p) => p.first == 'Q'), isEmpty);
    },
  );
}
