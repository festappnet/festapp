import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'floor is bounded, sparse, non-interactive and independent of seat identity',
    () {
      final base = tableLayout(shape: 'rect', count: 6);
      for (final style in ['wood', 'tile', 'carpet']) {
        final doc = base.copyWith(
          canvas: {...base.canvas, 'floorStyle': style},
        );
        expect(validateDocument(doc), isEmpty);
        expect(
          VenueLayoutDocument.fromJson(doc.toJson()).canvas['floorStyle'],
          style,
        );
        final scene = compileScene(doc);
        final floor =
            (scene['items'] as List).firstWhere((i) => i['kind'] == 'floor')
                as Map;
        expect(floor['nodeId'], isNull);
        expect(floor['hitPath'], isNull);
        final b = floor['bounds'] as Map;
        expect(b['x'], greaterThanOrEqualTo(doc.canvas['x']));
        expect(b['y'], greaterThanOrEqualTo(doc.canvas['y']));
        expect(
          (b['x'] as num) + (b['width'] as num),
          lessThanOrEqualTo(
            (doc.canvas['x'] as num) + (doc.canvas['width'] as num),
          ),
        );
        expect(
          (b['y'] as num) + (b['height'] as num),
          lessThanOrEqualTo(
            (doc.canvas['y'] as num) + (doc.canvas['height'] as num),
          ),
        );
        expect(
          doc.nodes.map((n) => n.toJson()),
          base.nodes.map((n) => n.toJson()),
        );
        final huge = doc.copyWith(
          canvas: {...doc.canvas, 'width': 100000, 'height': 100000},
        );
        final hugeFloor =
            (compileScene(huge)['items'] as List).firstWhere(
                  (i) => i['kind'] == 'floor',
                )
                as Map;
        expect((hugeFloor['path'] as List).length, lessThan(3200));
      }
      expect(
        (compileScene(base)['items'] as List).where(
          (i) => i['kind'] == 'floor',
        ),
        isEmpty,
      );
      final custom = base.copyWith(
        canvas: {...base.canvas, 'floorStyle': 'wood'},
        background: {
          'assetRef': 'floor',
          'hash': 'a' * 64,
          'width': 1600,
          'height': 1200,
          'x': 0,
          'y': 0,
          'rotation': 0,
          'scale': 1,
          'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
        },
      );
      expect(
        (compileScene(custom)['items'] as List).where(
          (i) => i['kind'] == 'floor',
        ),
        isEmpty,
      );
    },
  );
}
