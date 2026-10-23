import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument arrow([Object? length]) => VenueLayoutDocument(
  nodes: [
    LayoutNode(
      id: '10000000-0000-4000-8000-000000000001',
      kind: 'shape',
      width: 100,
      height: 80,
      properties: {
        'shape': 'arrow',
        'points': [
          [-50, 0],
          [50, 0],
        ],
        'arrowHeadLength': ?length,
      },
      style: {'fill': '#00000000', 'stroke': '#000000FF'},
    ),
  ],
);

List path(VenueLayoutDocument document) =>
    ((compileScene(document)['items'] as List).first as Map)['path'] as List;

void main() {
  test(
    'default arrow head stays unchanged and explicit length scales open head',
    () {
      final original = path(arrow());
      expect(path(arrow(12)), original);
      expect(original[2][0], 'M');
      expect(original[2][1], closeTo(50 - 12 * math.cos(.5), 1 / 1024));
      final enlarged = path(arrow(32));
      expect(enlarged.take(2).toList(), original.take(2).toList());
      expect(enlarged[2][1], closeTo(50 - 32 * math.cos(.5), 1 / 1024));
      expect(enlarged[2][2], closeTo(32 * math.sin(.5), 1 / 1024));
      expect(enlarged.last[0], 'L');
      expect(validateDocument(arrow(32)), isEmpty);
    },
  );
  test(
    'arrow head length rejects nonpositive nonfinite and nonnumeric values',
    () {
      for (final value in <Object>[0, -1, double.infinity, double.nan, '32']) {
        expect(
          validateDocument(arrow(value)).map((issue) => issue.reason),
          contains('invalid_arrow_head_length'),
        );
      }
    },
  );
}
