import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';
import 'support/style.dart';

void main() {
  for (final style in [
    'plain',
    'round',
    'wood',
    'upholstered',
    'roundUpholstered',
    'banquet',
    'transit',
  ]) {
    for (final state in [
      {'status': 'occupied'},
      {'selected': true},
      {'pending': true},
    ]) {
      test('$style marker stays centered on the cushion: $state', () {
        final seat = LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          x: 120,
          y: 90,
          width: 44,
          height: 40,
          rotation: 90,
        );
        final doc = withKindStyle(VenueLayoutDocument(nodes: [seat]), 'seat', {
          'seatStyle': style,
        });
        final scene = compileScene(doc, presentation: {seat.id: state});
        final item = (scene['items'] as List).singleWhere(
          (i) => i['id'] == '${seat.id}:state',
        );
        final matrix = (item['matrix'] as List)
            .map((n) => (n as num).toDouble())
            .toList();
        final path = item['path'] as List;
        final points = [
          for (final p in path)
            transformPoint(
              matrix,
              (p[1] as num).toDouble(),
              (p[2] as num).toDouble(),
            ),
        ];
        final scaled = state['selected'] == true
            ? layoutSelectedSeatScale
            : 1.0;
        // Expected cushion geometry is deliberately independent of marker implementation.
        final (cy, halfHeight) = switch (style) {
          'wood' => (-5.8, 14.2),
          'upholstered' => (-5.6, 14.4),
          'roundUpholstered' => (-4.0, 16.0),
          'banquet' => (-4.6, 13.8),
          'transit' => (-5.2, 13.6),
          _ => (0.0, 20.0),
        };
        final center = transformPoint(worldMatrix(doc, seat), 0, cy * scaled);
        // X and pending are symmetric; the check's visual center has its own offset.
        if (state['selected'] != true) {
          final minX = points.map((p) => p[0]).reduce(min),
              maxX = points.map((p) => p[0]).reduce(max);
          final minY = points.map((p) => p[1]).reduce(min),
              maxY = points.map((p) => p[1]).reduce(max);
          expect((minX + maxX) / 2, closeTo(center[0], .02));
          expect((minY + maxY) / 2, closeTo(center[1], .02));
        } else {
          expect(matrix.sublist(0, 4), [1, 0, 0, 1]);
          expect(matrix[4], closeTo(center[0], .02));
          expect(matrix[5], closeTo(center[1], .02));
        }
        if (state['selected'] != true) {
          for (final point in points) {
            final local = transformPoint(
              inverseMatrix(worldMatrix(doc, seat)),
              point[0],
              point[1],
            );
            expect((local[1] - cy).abs(), lessThan(halfHeight));
          }
        }
        expect(
          compileSceneNodes(
            doc,
            {seat.id},
            presentation: {seat.id: state},
          )['items'],
          scene['items'],
        );
      });
    }
  }
}
