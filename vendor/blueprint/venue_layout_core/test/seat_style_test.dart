import 'support/style.dart';
import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  final chair = LayoutNode(
    id: newLayoutId(),
    kind: 'seat',
    x: 200,
    y: 180,
    width: 44,
    height: 40,
    rotation: 127,
    style: {},
  );
  final plain = VenueLayoutDocument(nodes: [chair]);
  test('plain default leaves canonical scene unchanged', () {
    final explicit = withKindStyle(plain, 'seat', {'seatStyle': 'plain'});
    expect(compileScene(explicit), compileScene(plain));
    expect(explicit.nodes.single, same(chair));
  });
  test(
    'round family renders authored elliptical dimensions without accents',
    () {
      final document = withLayoutMaterialFamily(plain, 'round');
      expect(validateDocument(document), isEmpty);
      final items = compileScene(document)['items'] as List;
      final body = items.singleWhere((item) => item['id'] == chair.id) as Map;
      final path = body['path'] as List;
      final points = path.where((command) => command.first != 'Z');
      for (final command in points) {
        final x = (command[1] as num).toDouble();
        final y = (command[2] as num).toDouble();
        expect(
          x * x / pow(chair.width / 2, 2) + y * y / pow(chair.height / 2, 2),
          closeTo(1, .001),
        );
      }
      expect(body['hitPath'], body['path']);
      expect(
        items.where((item) => item['id'] == '${chair.id}:seat-style'),
        isEmpty,
      );
      expect(document.nodes, plain.nodes);
      expect(LayoutSpatialIndex(document).hitTest(200, 180), chair.id);
      expect(LayoutSpatialIndex(document).hitTest(221, 199), isNull);
      final matrix = worldMatrices(document)[chair.id]!;
      final inside = transformPoint(matrix, 21, 0);
      final outside = transformPoint(matrix, 23, 0);
      expect(
        LayoutSpatialIndex(document).hitTest(inside[0], inside[1]),
        chair.id,
      );
      expect(
        LayoutSpatialIndex(document).hitTest(outside[0], outside[1]),
        isNull,
      );
      final restored = VenueLayoutDocument.fromJson(document.toJson());
      expect(compileScene(restored), compileScene(document));
      final switched = withLayoutMaterialFamily(document, 'wood');
      expect(
        (compileScene(switched)['items'] as List).where(
          (item) => item['id'] == '${chair.id}:seat-style',
        ),
        hasLength(1),
      );
    },
  );
  for (final style in ['wood', 'upholstered', 'roundUpholstered']) {
    test(
      '$style uses one construction decoration without new geometry or hit targets',
      () {
        final d = withKindStyle(plain, 'seat', {'seatStyle': style});
        final before = compileScene(plain)['items'] as List;
        final scene = compileScene(d), items = scene['items'] as List;
        final accent =
            items.singleWhere((i) => i['id'] == '${chair.id}:seat-style')
                as Map;
        expect(items.length, before.length + 1);
        expect(accent['kind'], 'decoration');
        expect(accent['nodeId'], chair.id);
        expect(accent.containsKey('hitPath'), isFalse);
        expect(accent['fill'], style == 'wood' ? '#B88755FF' : '#00000000');
        expect(accent['matrix'], (items.first as Map)['matrix']);
        final body = (items.first as Map);
        expect(body['path'], isNot((before.first as Map)['path']));
        expect(body['hitPath'], body['path']);
        expect(
          (body['path'] as List).where((command) => command.first == 'M'),
          hasLength(2),
          reason: 'Only a seat and one backrest',
        );
        expect(
          (accent['path'] as List).where((command) => command.first == 'M'),
          hasLength(1),
          reason: 'No decorative legs or concentric cushion rings',
        );
        for (final key in ['id', 'matrix', 'fill', 'stroke', 'strokeWidth']) {
          expect(body[key], (before.first as Map)[key]);
        }
        expect(items.where((i) => i.containsKey('hitPath')).length, 1);
        expect(d.nodes, plain.nodes);
        expect(d.canvas, plain.canvas);
        expect(
          worldHull(d.nodes.single, worldMatrix(d, chair)),
          worldHull(chair, worldMatrix(plain, chair)),
        );
        expect(LayoutSpatialIndex(d).hitTest(200, 180), chair.id);
        expect(LayoutSpatialIndex(d).hitTest(800, 800), isNull);
        expect(compileSceneNodes(d, {chair.id})['items'], items);
        expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
        final maxX = chair.width / 2, maxY = chair.height / 2;
        for (final command in accent['path'] as List) {
          for (var i = 1; i < command.length; i += 2) {
            expect((command[i] as num).abs(), lessThanOrEqualTo(maxX + .01));
            expect(
              (command[i + 1] as num).abs(),
              lessThanOrEqualTo(maxY + .01),
            );
          }
        }
      },
    );
    test('$style preserves presentation colors above palette and accents', () {
      final d = withKindStyle(plain, 'seat', {
        'seatStyle': style,
        'fill': '#AA8855FF',
      });
      for (final state in [
        {'selected': true},
        {'status': 'occupied'},
        {'pending': true},
      ]) {
        final items =
            compileScene(d, presentation: {chair.id: state})['items'] as List;
        final body = items.firstWhere((i) => i['id'] == chair.id),
            accent = items.firstWhere(
              (i) => i['id'] == '${chair.id}:seat-style',
            );
        expect(
          body['fill'],
          state['selected'] == true
              ? '#267329FF'
              : state['status'] == 'occupied'
              ? '#94A3B8FF'
              : '#AA8855FF',
        );
        expect(accent['stroke'], '#FFFFFF80');
        expect(items.last['kind'], 'state');
      }
    });
  }

  test('couch cushions retain sofa rendering and atomic membership', () {
    final couch = couchLayout(count: 3);
    final d = withKindStyle(couch, 'seat', {'seatStyle': 'wood'});
    expect(
      (compileScene(d)['items'] as List).where(
        (i) => (i['id'] as String).endsWith(':seat-style'),
      ),
      isEmpty,
    );
    expect(d.selectionUnits, couch.selectionUnits);
    expect(d.nodes, couch.nodes);
  });
}
