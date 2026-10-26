import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'seat labels stay in data and accessibility but never produce glyphs',
    () {
      final seat = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 100,
        y: 100,
        label: '12',
      );
      final document = VenueLayoutDocument(nodes: [seat]);
      for (final presentation in <Map<String, dynamic>>[
        {},
        {
          seat.id: {'label': '99', 'selected': true},
        },
      ]) {
        final scene = compileScene(document, presentation: presentation);
        expect(
          (scene['items'] as List).where((item) => item['kind'] == 'glyphs'),
          isEmpty,
        );
        expect(
          (scene['items'] as List).any((item) => item['id'] == seat.id),
          true,
        );
        expect(scene['issues'], isEmpty);
        expect(
          VenueLayoutDocument.fromJson(document.toJson()).nodes.single.label,
          '12',
        );
      }
    },
  );
}
