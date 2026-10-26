import 'package:venue_layout_core/venue_layout_core.dart';

/// Approved round-table ballroom; all chairs remain automatic native seats.
VenueLayoutDocument approvedRoundBall() {
  final nodes = <LayoutNode>[
    LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 1200,
      y: 256,
      width: 1080,
      height: 180,
      properties: {'shape': 'rect', 'role': 'obstacle', 'obstacle': true},
    ),
    LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      x: 1200,
      y: 256,
      width: 1080,
      height: 80,
      label: 'Stage',
      properties: const {'text': 'Stage'},
      style: {
        'label': {'size': 64, 'weight': 700, 'align': 'center'},
      },
    ),
  ];
  final attachments = <Map<String, dynamic>>[];
  var index = 0;
  for (final y in [150.0, 260.0, 370.0]) {
    for (final x in [106.0, 235.0, 364.0, 493.0]) {
      final d = tableLayout(
        shape: 'circle',
        count: 8,
        x: x * 4,
        y: y * 4,
        width: 200,
        height: 200,
        seating: const TableSeating(
          width: 52,
          height: 52,
          gap: 12,
          spacing: 12,
          edgePadding: 8,
        ),
      );
      final number = '${++index}';
      nodes.addAll(
        d.nodes.map(
          (n) => n.kind == 'table'
              ? n.copyWith(
                  label: number,
                  style: {
                    'label': {'size': 48, 'weight': 700},
                  },
                )
              : n,
        ),
      );
      attachments.addAll(d.attachments);
    }
  }
  return withLayoutStudioPalette(
    withLayoutMaterialFamily(
      VenueLayoutDocument(
        nodes: nodes,
        attachments: attachments,
        canvas: {
          'x': 0,
          'y': 0,
          'width': 2400,
          'height': 1800,
          'fill': '#FFFFFFFF',
        },
        styles: {
          'label': {'size': 48, 'weight': 700, 'align': 'center'},
        },
      ),
      'wood',
    ),
    'Champagne',
  );
}
