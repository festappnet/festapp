import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final explicitNull in [false, true]) {
    test(
      'v1 ${explicitNull ? 'null' : 'omitted'} unit kind is rejected by canonical admission',
      () {
        final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 200),
            b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 260, y: 200);
        final source = <String, dynamic>{
          'id': newLayoutId(),
          'nodeIds': [a.id, b.id],
          if (explicitNull) 'kind': null,
        };
        final document = VenueLayoutDocument(
          nodes: [a, b],
          selectionUnits: [source],
        );
        expect(source.containsKey('kind'), explicitNull);
        expect(
          validateDocument(document).map((i) => i.reason),
          contains('invalid_selection_unit_kind'),
        );
        final json = VenueLayoutDocument(nodes: [a, b]).toJson();
        json['selectionUnits'] = [source];
        expect(
          () => VenueLayoutDocument.fromJson(json),
          throwsA(isA<InvalidLayoutDocument>()),
        );
      },
    );
  }
  test(
    'explicit unknown unit kind remains a typed rejection with original payload',
    () {
      final seat = LayoutNode(id: newLayoutId(), kind: 'seat');
      final document = VenueLayoutDocument(
        nodes: [seat],
        selectionUnits: [
          {
            'id': newLayoutId(),
            'nodeIds': [seat.id],
            'kind': 'partial',
          },
        ],
      );
      expect(
        validateDocument(
          document,
        ).any((i) => i.reason == 'invalid_selection_unit_kind'),
        isTrue,
      );
      final json = VenueLayoutDocument(nodes: [seat]).toJson();
      json['selectionUnits'] = [
        {
          'id': newLayoutId(),
          'nodeIds': [seat.id],
          'kind': 'partial',
        },
      ];
      expect(
        () => VenueLayoutDocument.fromJson(json),
        throwsA(
          isA<InvalidLayoutDocument>().having(
            (e) => (e.original['selectionUnits'] as List).single['kind'],
            'original kind',
            'partial',
          ),
        ),
      );
    },
  );
}
