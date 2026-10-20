import 'dart:math' as math;
import 'package:venue_layout_core/venue_layout_core.dart';

const cinemaCanvasFill = '#071326FF';
const cinemaKindStyles = <String, Map<String, dynamic>>{
  'seat': {
    'material': 'minimal',
    'seatStyle': 'upholstered',
    'fill': '#5930E8FF',
    'stroke': '#3020A0FF',
    'strokeWidth': 0.0,
    'cornerRadius': 12.0,
  },
  'furniture': {
    'material': 'simple',
    'fill': '#3822A7FF',
    'stroke': '#9980FFFF',
    'strokeWidth': 1.5,
    'cornerRadius': 10.0,
  },
  'table': {
    'material': 'lounge',
    'fill': '#3434B6FF',
    'stroke': '#7665E5FF',
    'cornerRadius': 12.0,
    'label': {'color': '#FFFFFFFF'},
  },
  'text': {
    'label': {'color': '#F5F3FFFF'},
  },
};

VenueLayoutDocument withCinemaAppearance(VenueLayoutDocument document) =>
    document.copyWith(
      canvas: {...document.canvas, 'fill': cinemaCanvasFill},
      styles: {
        ...document.styles,
        'label': {
          ...document.styles['label'] as Map? ?? {},
          'color': '#F5F3FFFF',
        },
        'kinds': {
          ...document.styles['kinds'] as Map? ?? {},
          for (final entry in cinemaKindStyles.entries)
            entry.key: {
              ...document.styles['kinds']?[entry.key] as Map? ?? {},
              ...entry.value,
            },
        },
      },
    );

/// Straight screen-facing back, rounded front corners, as in a cinema seat.
Map<String, dynamic> cinemaSeatShape(double width, double height) {
  final w = width / 2, h = height / 2, radius = height * .30;
  return {
    'symbol': 'chair',
    'shape': 'polygon',
    'points': [
      [-w, -h],
      [w, -h],
      [w, h - radius],
      for (var i = 1; i <= 8; i++)
        [
          w - radius + radius * math.cos(i * math.pi / 16),
          h - radius + radius * math.sin(i * math.pi / 16),
        ],
      [-w + radius, h],
      for (var i = 1; i <= 8; i++)
        [
          -w + radius + radius * math.cos(math.pi / 2 + i * math.pi / 16),
          h - radius + radius * math.sin(math.pi / 2 + i * math.pi / 16),
        ],
    ],
  };
}

/// Seven rows, a side aisle and four real two-seat sofa assemblies (84 seats).
VenueLayoutDocument galaxyCinemaHall() {
  final nodes = <LayoutNode>[];
  final units = <Map<String, dynamic>>[];
  final attachments = <Map<String, dynamic>>[];
  void text(double x, double y, String label, double width) => nodes.add(
    LayoutNode(
      id: newLayoutId(),
      kind: 'text',
      x: x,
      y: y,
      width: width,
      height: 44,
      properties: {'text': label},
      style: const {
        'label': {'color': '#F5F3FFFF', 'size': 28, 'align': 'center'},
      },
    ),
  );
  for (var i = 0; i < 110; i++) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 25.0 + (i * 419) % 1850,
        y: 20.0 + (i * 163) % 1180,
        width: i % 9 == 0 ? 4 : 2,
        height: i % 9 == 0 ? 4 : 2,
        properties: const {'shape': 'ellipse', 'role': 'decoration'},
        style: {
          'fill': i % 9 == 0 ? '#AABFEA66' : '#7B95C333',
          'strokeWidth': 0,
        },
      ),
    );
  }
  text(1110, 65, 'Screen', 1000);
  nodes.add(
    LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 1110,
      y: 115,
      width: 1120,
      height: 5,
      properties: const {'shape': 'rect', 'role': 'decoration'},
      style: const {'fill': '#7860EEFF', 'strokeWidth': 0},
    ),
  );
  for (var row = 0; row < 7; row++) {
    final letter = String.fromCharCode(71 - row), y = 240.0 + row * 135;
    text(70, y, letter, 50);
    text(1820, y, letter, 50);
    for (var col = 0; col < 12; col++) {
      final x = col < 2 ? 235.0 + col * 105 : 660.0 + (col - 2) * 108;
      if (row.isOdd && col == 6) {
        final couch = couchLayout(
          x: x + 54,
          y: y,
          width: 194,
          height: 88,
          count: 2,
        );
        nodes.addAll(
          couch.nodes.map(
            (n) => n.copyWith(
              label: n.kind == 'seat'
                  ? '$letter${col + 1 + couch.nodes.where((s) => s.kind == 'seat').toList().indexOf(n)}'
                  : '$letter${col + 1}-${col + 2}',
              rotation: isCouchNode(n) ? 180 : n.rotation,
              style: n.kind == 'seat' ? const {'cornerRadius': 8.0} : const {},
            ),
          ),
        );
        units.addAll(couch.selectionUnits);
        attachments.addAll(couch.attachments);
        col++;
        continue;
      }
      nodes.add(
        LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          x: x,
          y: y,
          width: 80,
          height: 80,
          label: '$letter${col + 1}',
          properties: cinemaSeatShape(80, 80),
          style: {
            'fill': row.isEven ? '#4E2DE1FF' : '#3548DDFF',
            'cornerRadius': 1,
          },
        ),
      );
    }
  }
  // A fourth sofa in the front row, retaining the same twelve-seat row capacity.
  final pair = nodes
      .where((n) => n.kind == 'seat' && const {'A7', 'A8'}.contains(n.label))
      .toList();
  nodes.removeWhere((n) => pair.any((p) => p.id == n.id));
  final front = couchLayout(x: 1146, y: 1050, width: 194, height: 88, count: 2);
  var slot = 7;
  nodes.addAll(
    front.nodes.map(
      (n) => n.copyWith(
        label: n.kind == 'seat' ? 'A${slot++}' : 'A7-8',
        rotation: isCouchNode(n) ? 180 : n.rotation,
        style: n.kind == 'seat' ? const {'cornerRadius': 8.0} : const {},
      ),
    ),
  );
  units.addAll(front.selectionUnits);
  attachments.addAll(front.attachments);
  return withCinemaAppearance(
    VenueLayoutDocument(
      canvas: const {
        'x': 0,
        'y': 0,
        'width': 1900,
        'height': 1220,
        'fill': cinemaCanvasFill,
      },
      nodes: nodes,
      selectionUnits: units,
      attachments: attachments,
    ),
  );
}
