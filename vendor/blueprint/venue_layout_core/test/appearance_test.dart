import 'support/style.dart';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

Map<String, dynamic> item(
  VenueLayoutDocument d,
  String id, {
  Map<String, dynamic> presentation = const {},
  Map<String, dynamic> resources = const {},
}) =>
    (compileScene(d, presentation: presentation, resources: resources)['items']
            as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((i) => i['id'] == id);

void main() {
  test(
    'occupied marker can be hidden without changing status or pending feedback',
    () {
      final d = tableLayout(shape: 'rect', count: 2);
      final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
      List states(Map<String, dynamic> state) =>
          (compileScene(d, presentation: {seat.id: state})['items'] as List)
              .where((item) => item['id'] == '${seat.id}:state')
              .toList();
      expect(states({'status': 'occupied'}), hasLength(1));
      expect(states({'status': 'occupied', 'stateMarker': 'none'}), isEmpty);
      expect(
        states({'status': 'occupied', 'stateMarker': 'none', 'pending': true}),
        hasLength(1),
      );
      expect(
        item(
          d,
          seat.id,
          presentation: {
            seat.id: {
              'status': 'occupied',
              'stateMarker': 'none',
              'fill': '#412673FF',
            },
          },
        )['fill'],
        '#412673FF',
      );
    },
  );

  test('corner paths affect tables seats and partial scene identically', () {
    var d = tableLayout(shape: 'rect', count: 2);
    final table = d.nodes.first,
        seat = d.nodes.firstWhere((n) => n.kind == 'seat');
    for (final kind in ['table', 'seat']) {
      d = withKindStyle(d, kind, {'cornerRadius': 0, 'fill': '#123456FF'});
    }
    for (final n in [table, seat]) {
      final square = item(d, n.id);
      expect((square['path'] as List).any((c) => c.first == 'Q'), isFalse);
      final rounded = withKindStyle(d, n.kind, {'cornerRadius': 12});
      expect(
        (item(rounded, n.id)['path'] as List).any((c) => c.first == 'Q'),
        isTrue,
      );
      final full = compileScene(rounded)['items'] as List;
      final partial = compileSceneNodes(rounded, {n.id})['items'] as List;
      expect(
        partial,
        full.where((i) => i['id'] == n.id || i['nodeId'] == n.id).toList(),
      );
    }
  });
  test('open geometry stays transparent while polygons inherit fill', () {
    final nodes = [
      for (final shape in ['line', 'polyline', 'arrow', 'polygon'])
        shapeFromPoints(shape, [
          [0, 0],
          [100, 0],
          [100, 80],
        ]),
    ];
    final d = withKindStyle(VenueLayoutDocument(nodes: nodes), 'shape', {
      'fill': '#AABBCCFF',
      'strokeWidth': 5,
    });
    for (final n in nodes) {
      expect(
        item(d, n.id)['fill'],
        n.properties['shape'] == 'polygon' ? '#AABBCCFF' : '#00000000',
      );
      expect(item(d, n.id)['strokeWidth'], 5);
      if (n.properties['shape'] != 'polygon') {
        expect(
          item(
            d,
            n.id,
            presentation: {
              n.id: {'selected': true},
            },
          )['fill'],
          '#00000000',
        );
      }
    }
  });
  test('presentation states win over inherited and local fill', () {
    final base = couchLayout();
    final d = withKindStyle(
      base.copyWith(
        nodes: [
          for (final n in base.nodes)
            n.kind == 'seat' ? n.copyWith(style: {}) : n,
        ],
      ),
      'seat',
      {'fill': '#ABCDEF88'},
    );
    final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
    expect(item(d, seat.id)['fill'], '#ABCDEF88');
    expect(
      item(
        d,
        seat.id,
        presentation: {
          seat.id: {'selected': true},
        },
      )['fill'],
      '#267329FF',
    );
    expect(
      item(
        d,
        seat.id,
        presentation: {
          seat.id: {'status': 'occupied'},
        },
      )['fill'],
      '#94A3B8FF',
    );
    expect(
      item(
        d,
        seat.id,
        presentation: {
          seat.id: {'fill': '#112233FF', 'selected': true},
        },
      )['fill'],
      '#112233FF',
    );
  });
}
