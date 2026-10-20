import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

const tableId = '10000000-0000-4000-8000-000000000001';
const seatId = '10000000-0000-4000-8000-000000000002';
VenueLayoutDocument document({
  Map<String, dynamic> styles = const {},
  Map<String, dynamic> child = const {},
  Map<String, dynamic> seat = const {},
}) => VenueLayoutDocument(
  schemaVersion: 2,
  styles: styles,
  nodes: [
    LayoutNode(
      id: tableId,
      kind: 'table',
      width: 200,
      height: 100,
      surface: const {'type': 'rect'},
      childStyles: child,
    ),
    LayoutNode(id: seatId, kind: 'seat', parentId: tableId, style: seat),
  ],
);
void main() {
  test(
    'canonical records roundtrip without legacy appearance or text-style fields',
    () {
      final d = document(
        styles: const {
          'label': {'size': 28},
          'kinds': {
            'seat': {'fill': '#ff0000ff'},
          },
        },
        child: const {
          'seat': {
            'label': {'weight': 700},
          },
        },
      );
      expect(validateDocument(d), isEmpty);
      final json = d.toJson();
      expect(json['schemaVersion'], 2);
      expect(json.containsKey('appearance'), isFalse);
      expect(json.containsKey('defaultTextStyle'), isFalse);
      expect(VenueLayoutDocument.fromJson(json).toJson(), json);
    },
  );
  test(
    'leaf cascade and provenance follow document, kind, direct table and own declaration',
    () {
      final d = document(
        styles: const {
          'label': {'size': 24, 'italic': true},
          'kinds': {
            'seat': {
              'fill': '#ff0000ff',
              'label': {'size': 30},
            },
          },
        },
        child: const {
          'seat': {
            'fill': '#00ff00ff',
            'label': {'weight': 700, 'size': 36},
          },
        },
        seat: const {
          'label': {'size': 36, 'italic': false},
        },
      );
      final resolved = resolveNodeAppearance(d, d.nodes.last);
      expect(resolved.values['fill'], '#00ff00ff');
      expect(resolved.label['size'], 36);
      expect(resolved.label['weight'], 700);
      expect(resolved.label['italic'], false);
      expect(resolved.sources['label.size'], 'node:$seatId');
      expect(resolved.sources['fill'], 'table:$tableId');
      final reset = patchCanonicalStyle(d.nodes.last.style, [
        'label',
        'size',
      ], unset: true);
      expect(reset, {
        'label': {'italic': false},
      });
      final inherited = resolveNodeAppearance(
        d,
        d.nodes.last.copyWith(style: reset),
      );
      expect(inherited.label['size'], 36);
      expect(inherited.sources['label.size'], 'table:$tableId');
      expect(
        () => patchCanonicalStyle(reset, ['label', 'size'], value: null),
        throwsFormatException,
      );
    },
  );
  test(
    'locked nodes inherit shared styles and new seats inherit table child styles',
    () {
      final d = document(
        child: const {
          'seat': {
            'fill': '#123456ff',
            'label': {'size': 32},
          },
        },
      );
      expect(
        resolveNodeAppearance(
          d,
          d.nodes.last.copyWith(locked: true),
        ).values['fill'],
        '#123456ff',
      );
      final other = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: tableId,
      );
      expect(resolveNodeAppearance(d, other).label['size'], 32);
      expect(other.style, isEmpty);
    },
  );
  test(
    'each material declaration expands inside its own layer before explicit leaves',
    () {
      final d = document(
        styles: const {
          'kinds': {
            'seat': {'material': 'wood', 'strokeWidth': 7},
          },
        },
        seat: const {'material': 'lounge', 'cornerRadius': 3},
      );
      final resolved = resolveNodeAppearance(d, d.nodes.last);
      expect(resolved.values['material'], 'lounge');
      expect(resolved.values['cornerRadius'], 3);
      expect(resolved.values['strokeWidth'], 1.2);
      expect(resolved.sources['strokeWidth'], 'node:$seatId');
    },
  );
  test(
    'canonical admission rejects legacy properties, null, unknown style fields and malformed placement',
    () {
      final d = document();
      for (final n in [
        d.nodes.last.copyWith(properties: const {'fontId': 'legacy'}),
        d.nodes.last.copyWith(
          style: const {
            'label': {'size': null},
          },
        ),
        d.nodes.last.copyWith(style: const {'unknown': 1}),
      ])
        expect(
          validateDocument(d.copyWith(nodes: [d.nodes.first, n])),
          isNotEmpty,
        );
      expect(
        validateDocument(
          d.copyWith(
            attachments: [
              {
                'seatId': seatId,
                'targetId': tableId,
                'rotationMode': 'auto',
                'placement': {'mode': 'free', 'x': 10},
              },
            ],
          ),
        ),
        isNotEmpty,
      );
      expect(
        validateDocument(
          d.copyWith(
            attachments: [
              {
                'seatId': seatId,
                'targetId': tableId,
                'rotationMode': 'manual',
                'placement': {'mode': 'free'},
              },
            ],
          ),
        ),
        isEmpty,
      );
    },
  );
  test(
    'grid rings are authoritative, bounded and do not move or regenerate seats on read',
    () {
      final d = document();
      final table = d.nodes.first.copyWith(
        width: 200,
        height: 100,
        surface: const {
          'type': 'grid',
          'moduleSize': 50,
          'outer': [
            [0, 0],
            [4, 0],
            [4, 2],
            [0, 2],
          ],
          'holes': [],
        },
      );
      final grid = d.copyWith(nodes: [table, d.nodes.last]);
      expect(validateDocument(grid), isEmpty);
      expect(surfaceGeometryProperties(table)['points'], [
        [-100.0, -50.0],
        [100.0, -50.0],
        [100.0, 50.0],
        [-100.0, 50.0],
      ]);
      final read = VenueLayoutDocument.fromJson(grid.toJson());
      expect(
        read.nodes.firstWhere((n) => n.id == seatId).toJson(),
        d.nodes.last.toJson(),
      );
      expect(
        validateDocument(
          grid.copyWith(nodes: [table.copyWith(width: 201), d.nodes.last]),
        ),
        isNotEmpty,
      );
    },
  );
}
