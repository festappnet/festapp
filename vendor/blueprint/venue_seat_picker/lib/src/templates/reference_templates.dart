import 'dart:math' as math;
import 'package:venue_layout_core/venue_layout_core.dart';
import 'reference_geometry.dart';

/// Public venue plans traced into editable native objects, at raster proportions.
/// These are seating configurations, not measured building surveys.
const referenceTemplateSpecs = [
  (
    id: 'reference-belvedere',
    title: 'Belvedere - ples s balkónem',
    seats: 110,
    description: '20 natočených stolů, 10 zadních sedadel a nečíslovaný balkón',
    material: 'round',
    palette: 'Forest',
  ),
  (
    id: 'reference-lipoltice',
    title: 'Lipoltice - včelařský ples',
    seats: 186,
    description: '14 podlouhlých stolů, taneční parket a přísálí',
    material: 'minimal',
    palette: 'Forest',
  ),
  (
    id: 'reference-brandys',
    title: 'Kino Brandýs - úplná sestava',
    seats: 265,
    description: '223 pevných míst a 42 přístavných ve třech předních řadách',
    material: 'lounge',
    palette: 'Cinema red',
  ),
  (
    id: 'reference-lucerna',
    title: 'Lucerna - Velký sál / ples',
    seats: 1066,
    description: 'Plesová konfigurace pořadatele, přízemí a dva balkóny',
    material: 'minimal',
    palette: 'Forest',
  ),
];

VenueLayoutDocument createReferenceTemplate(String id) {
  final spec = referenceTemplateSpecs.firstWhere((s) => s.id == id);
  final key = id.substring('reference-'.length);
  final data = referenceGeometry[key] as Map;
  final b = _ReferenceBuilder(
    key == 'belvedere'
        ? 1737
        : key == 'lucerna'
        ? 1560
        : key == 'brandys'
        ? 1920
        : key == 'ostrava'
        ? 1120
        : 717,
    key == 'belvedere'
        ? 2136
        : key == 'lucerna'
        ? 1033
        : key == 'brandys'
        ? 1100
        : key == 'ostrava'
        ? 1000
        : 665,
    tableLabelSize: key == 'lucerna'
        ? 44
        : key == 'belvedere'
        ? 88
        : key == 'ostrava'
        ? 56
        : 48,
  );
  if (key == 'lipoltice' || key == 'ostrava' || key == 'belvedere') {
    for (final raw in data['tables'] as List) {
      final t = raw as Map;
      if (key == 'belvedere') {
        b.customTable(t);
        continue;
      }
      b.table(
        t,
        key == 'belvedere'
            ? 30
            : key == 'lipoltice'
            ? 12
            : 17,
        key == 'belvedere'
            ? 30
            : key == 'lipoltice'
            ? 12
            : 17,
        lipoltice: key == 'lipoltice',
      );
    }
  }
  switch (key) {
    case 'belvedere':
      b.box(81.5, 81.5, 1574, 1973, '', fill: '#FFFFFFFF', z: -10);
      b.nodes.add(
        shapeFromPoints(
          'polygon',
          [
            [163, 436],
            [273, 436],
            [273, 1783],
            [1465, 1783],
            [1465, 436],
            [1575, 436],
            [1575, 1893],
            [163, 1893],
          ].map((p) => [p[0] * 4.0, p[1] * 4.0]).toList(),
          properties: {'role': 'decoration'},
        ).copyWith(z: -9, style: {'fill': '#F2D37AFF'}),
      );
      b.path([
        [81.5, 354.5],
        [304.5, 354.5],
        [354.5, 404.5],
        [354.5, 1651],
        [404.5, 1701],
        [1333, 1701],
        [1383, 1651],
        [1383, 404.5],
        [1433, 354.5],
        [1655, 354.5],
      ]);
      b.box(549, 163, 640, 110, 'Pódium');
      for (final raw in data['seats'] as List) {
        final seat = raw as List;
        b.seat(
          (seat[0] as num).toDouble(),
          (seat[1] as num).toDouble(),
          30,
          30,
          seat[2] as String,
          180,
        );
      }
      b.text(870, 1600, 'Přízemí', 300);
      b.text(870, 1840, 'Balkón / sezení', 500);
      b.text(870, 1970, 'Nečíslovaná zóna - kapacita neuvedena', 950);
      b.section('Přízemí a balkón podle prodejního plánku');

    case 'lipoltice':
      for (final raw in data['walls'] as List) {
        b.wall(raw as Map, fill: '#CDD6D0FF');
      }
      b.box(615, 213, 72, 36, 'Kapela');
      b.box(560, 372, 115, 44, 'Šatna');
      b.text(330, 270, 'Taneční parket', 170);
      b.text(119, 477, 'Pořadatelé', 130);
      b.text(160, 526, 'Vstupenky', 120);
      b.text(94, 591, 'Přísálí', 90);
      b.box(160, 602, 85, 43, 'Tombola');
      b.text(392, 530, 'Hostinec', 160);
      b.box(535, 448, 42, 70, 'Bar');
      b.box(305, 580, 110, 55, 'Výčep');
      b.box(270, 450, 37, 36, 'Krb');
      b.section('Sál a přísálí');
    case 'ostrava':
      for (final raw in data['walls'] as List) {
        b.path((raw as List).map((p) => (p as List).cast<num>()).toList());
      }
      b.box(260, 49, 325, 33, 'Jeviště');
      b.text(380, 330, 'Taneční parket', 230);
      b.text(828, 490, 'Přísálí', 90);
      b.text(330, 710, 'Galerie', 115);
      b.box(840.68, 844, 57.32, 154, 'Šatna');
      // The source calls this Galerie, without claiming it is an upper floor.

      b.section('Sál, přísálí a galerie');
    case 'brandys':
      b.box(56, 255, 1809, 734, '', fill: '#E6E7E6FF', z: -10);
      b.box(307, 255, 343, 734, '', fill: '#EBD9B8FF', z: -9);
      b.box(650, 340, 30, 565, '', fill: '#EBD9B8FF', z: -9);
      b.box(56, 255, 251, 734, 'Jeviště', fill: '#D7DAD9FF', z: -8);
      b.box(56, 372, 14, 505, '', fill: '#FFFFFFFF', z: -7);
      b.path([
        [56, 255],
        [420, 255],
      ]);
      b.path([
        [650, 255],
        [1705, 255],
      ]);
      b.path([
        [1798, 255],
        [1865, 255],
        [1865, 899],
      ]);
      b.path([
        [1865, 989],
        [56, 989],
        [56, 255],
      ]);
      b.path([
        [307, 255],
        [307, 989],
      ]);
      // Source door openings and entrance stairs, kept as native line geometry.
      for (final x in [420.0, 496.0, 573.0, 1705.0, 1751.0]) {
        final w = x > 1000 ? 46.0 : 76.0;
        b.path([
          [x, 255],
          [x, 215],
          [x + w / 2, 255],
          [x + w, 215],
          [x + w, 255],
        ]);
      }
      for (var step = 0; step < 6; step++) {
        b.path([
          [307 + step * 18, 255],
          [307 + step * 18, 379],
        ]);
      }
      b.path([
        [307, 379],
        [400, 379],
      ]);
      for (var step = 1; step < 4; step++) {
        b.path([
          [1705, 255 + step * 18],
          [1798, 255 + step * 18],
        ]);
      }
      b.path([
        [1798, 255],
        [1798, 327],
        [1705, 327],
        [1705, 255],
      ]);
      for (final raw in data['rows'] as List) {
        final r = raw as Map;
        final n = r['count'] as int;
        final d = rowLayout(
          rows: 1,
          seatsPerRow: n,
          x: (r['x'] as num).toDouble() * 4,
          y: (r['y'] as num).toDouble() * 4,
          spacing: (r['spacing'] as num).toDouble() * 4,
          seating: const TableSeating(
            width: 32 * 4,
            height: 31 * 4,
            spacing: 8 * 4,
          ),
        );
        final root = d.nodes.firstWhere((n) => n.parentId == null);
        b.nodes.addAll(
          d.nodes.map(
            (node) => node.id == root.id
                ? node.copyWith(rotation: 90, label: 'Řada ${r['label']}')
                : node.kind == 'seat'
                ? node.copyWith(
                    label: '${r['label']}/${node.label}',
                    rotation: 180,
                  )
                : node,
          ),
        );
        b.attachments.addAll(d.attachments);
        b.text((r['x'] as num).toDouble(), 303, '${r['label']}', 42, size: 88);
      }
      b.box(1648, 861, 38, 38, ''); // Source pillar replaces row 16, chair 14.
      b.text(550, 1040, 'Přístavné řady A-C', 300, size: 96);
      b.text(1220, 1040, 'Pevné řady 1-16', 420, size: 96);
      b.section('Kino - 223 pevných + 42 přístavných');
    case 'lucerna':
      // Retain original plan coordinates, with stacked balcony bands as drawn.
      b.box(96, 103, 1340, 915, '', fill: '#E8DDB6FF', z: -10);
      b.box(158, 204, 1260, 718, '', fill: '#F5EFD9FF', z: -9);
      b.box(240, 307, 1077, 506, '', fill: '#FFFFFFFF', z: -8);
      b.box(246, 415, 1019, 294, '', fill: '#E8E0CDFF', z: -7);
      b.box(246, 445, 191, 233, '', fill: '#33413BFF', z: -4);
      // Deliberate openings at the parquet entrances, and heavier balcony edges.
      for (final outline in [
        [
          [158, 411],
          [158, 200],
          [1417, 200],
        ],
        [
          [158, 711],
          [158, 922],
          [1417, 922],
        ],
        [
          [238, 411],
          [238, 301],
          [1317, 301],
        ],
        [
          [238, 711],
          [238, 813],
          [1317, 813],
        ],
      ]) {
        b.path(outline, thickness: 12);
      }
      b.path([
        [1417, 200],
        [1417, 922],
      ], thickness: 3);
      b.path([
        [1317, 301],
        [1317, 813],
      ], thickness: 3);
      for (final y in [170.0, 274.0, 377.0, 711.0, 815.0, 918.0]) {
        for (final x in [290.0, 417.0, 543.0, 670.0, 797.0, 924.0, 1052.0]) {
          if (x == 290 && (y == 377 || y == 711)) continue;
          b.pillar(x - 6.5, y, 13, 35);
        }
      }
      for (final level in ['ground', 'balcony_1', 'balcony_2']) {
        final first = b.nodes.length;
        for (final raw in data['tables'] as List) {
          final t = raw as Map;
          final tag = t['level'] as String;
          final match = level == 'ground'
              ? !tag.contains('balcony') && !tag.contains('galerie')
              : level == 'balcony_1'
              ? tag.contains('balcony_1')
              : tag.contains('balcony_2') || tag.contains('galerie');
          if (match) b.table(t, 5, 5, minSide: 16);
        }
        b.section(
          level == 'ground'
              ? 'Přízemí'
              : level == 'balcony_1'
              ? '1. balkón'
              : '2. balkón',
          first: first,
        );
      }
      b.text(770, 62, 'Lucerna / Velký sál / ples', 1000, size: 144);
      b.text(820, 562, 'Taneční parket', 620, size: 128);

      b.text(
        341,
        562,
        'Pódium',
        180,
        size: 112,
        rotation: -90,
        color: '#FFFFFFFF',
      );
      for (final item in [
        [126.0, 155.0, '2. balkón vpravo'],
        [126.0, 970.0, '2. balkón vlevo'],
        [200.0, 260.0, '1. balkón vpravo'],
        [200.0, 865.0, '1. balkón vlevo'],
        [272.0, 360.0, 'Přízemí vpravo'],
        [272.0, 762.0, 'Přízemí vlevo'],
        [1280.0, 153.0, '2. balkón vpravo'],
        [1280.0, 257.0, '1. balkón vpravo'],
        [1225.0, 361.0, 'Přízemí vpravo'],
        [1225.0, 762.0, 'Přízemí vlevo'],
        [1280.0, 865.0, '1. balkón vlevo'],
        [1280.0, 970.0, '2. balkón vlevo'],
      ]) {
        b.text(
          item[0] as double,
          item[1] as double,
          (item[2] as String)
              .replaceAll(' vpravo', '\nVPRAVO')
              .replaceAll(' vlevo', '\nVLEVO'),
          (item[2] as String).startsWith('Přízemí') ? 80 : 100,
          size: 80,
          rotation: -90,
        );
      }
      b.text(178, 368, 'Lóže', 80, size: 80, rotation: -90);
      b.text(178, 770, 'Lóže', 80, size: 80, rotation: -90);
      b.text(1398, 430, 'Lóže', 80, size: 80, rotation: -90);
      b.text(1398, 700, 'Lóže', 80, size: 80, rotation: -90);
      b.text(128, 770, 'Galerie', 100, size: 88, rotation: -90);
      // Steps/thresholds shown where the plan connects parquet and galleries.
      for (final xy in [
        [246.0, 417.0],
        [246.0, 695.0],
        [716.0, 400.0],
      ]) {
        for (var i = 0; i < 5; i++) {
          b.path([
            [xy[0], xy[1] + i * 3],
            [xy[0] + (xy[0] > 500 ? 38 : 48), xy[1] + i * 3],
          ]);
        }
      }
      for (var i = 0; i < 5; i++) {
        b.path([
          [1264 + i * 3.0, 498],
          [1264 + i * 3.0, 620],
        ]);
      }
  }
  final styled = withLayoutStudioPalette(
    withLayoutMaterialFamily(b.finish(), spec.material),
    spec.palette,
  );
  return styled.copyWith(
    styles: {
      ...styled.styles,
      'kinds': {
        ...styled.styles['kinds'] as Map,
        for (final kind in ['table', 'shape'])
          kind: {
            ...(styled.styles['kinds'] as Map)[kind] as Map,
            'strokeWidth': 4,
          },
      },
    },
  );
}

class _ReferenceBuilder {
  _ReferenceBuilder(this.width, this.height, {this.tableLabelSize = 48});
  final double width, height, tableLabelSize;
  final nodes = <LayoutNode>[];
  final attachments = <Map<String, dynamic>>[];
  final sections = <Map<String, dynamic>>[];
  void text(
    double x,
    double y,
    String value,
    double w, {
    double size = 64,
    double rotation = 0,
    String? color,
  }) {
    if (value.isEmpty) return;
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        x: x * 4,
        y: y * 4,
        width: w * 4,
        height: size * 1.55 * value.split('\n').length,
        rotation: rotation,
        z: 4,
        label: value,
        properties: {'text': value, 'role': 'decoration'},
        style: {
          'label': {
            'size': size,
            'weight': 700,
            'color': ?color,
            'align': 'center',
          },
        },
      ),
    );
  }

  void box(
    double x,
    double y,
    double w,
    double h,
    String label, {
    String? fill,
    int z = -3,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: (x + w / 2) * 4,
        y: (y + h / 2) * 4,
        width: w * 4,
        height: h * 4,
        z: z,
        style: {'fill': ?fill},
        properties: {'shape': 'rect', 'role': 'decoration'},
      ),
    );
    text(
      x + w / 2,
      y + h / 2,
      label,
      math.max(20, w - 8),
      size: label == 'Pódium' || label == 'Jeviště' ? 144 : 64,
    );
  }

  void wall(Map geometry, {required String fill, int z = -2}) {
    List<List<double>> points(List raw) => raw
        .map(
          (p) => [(p[0] as num).toDouble() * 4, (p[1] as num).toDouble() * 4],
        )
        .toList();
    nodes.add(
      shapeFromPoints(
        'polygon',
        points(geometry['points'] as List),
        properties: {
          'role': 'decoration',
          'holes': [
            for (final hole in geometry['holes'] as List) points(hole as List),
          ],
        },
      ).copyWith(
        z: z,
        style: {'fill': fill, 'stroke': '#526459FF', 'strokeWidth': 1},
      ),
    );
  }

  void pillar(double x, double y, double w, double h) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: (x + w / 2) * 4,
        y: (y + h / 2) * 4,
        width: w * 4,
        height: h * 4,
        z: -1,
        style: {'fill': '#42534AFF', 'cornerRadius': 16, 'strokeWidth': 0},
        properties: {
          'shape': 'roundedRect',
          'role': 'obstacle',
          'obstacle': true,
        },
      ),
    );
  }

  void path(List<List<num>> points, {double thickness = 2}) => nodes.add(
    shapeFromPoints(
      'polyline',
      points.map((p) => [p[0].toDouble() * 4, p[1].toDouble() * 4]).toList(),
      properties: {'role': 'decoration'},
    ).copyWith(style: {'strokeWidth': thickness * 4}),
  );
  void seat(
    double x,
    double y,
    double w,
    double h,
    String label,
    double rotation, {
    String? parent,
  }) {
    nodes.add(
      LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: x * 4,
        y: y * 4,
        width: w * 4,
        height: h * 4,
        rotation: rotation,
        parentId: parent,
        label: label,
        properties: const {},
      ),
    );
  }

  /// Authored positions for cabaret corners remain attached to real tables.
  void customTable(Map t) {
    final bounds = (t['bounds'] as List).cast<num>();
    final x = (bounds[0] + bounds[2] / 2).toDouble(),
        y = (bounds[1] + bounds[3] / 2).toDouble();
    final angle = (t['rotation'] as num? ?? 0).toDouble(),
        a = angle * math.pi / 180;
    final table = LayoutNode(
      id: newLayoutId(),
      kind: 'table',
      x: x * 4,
      y: y * 4,
      width: bounds[2].toDouble() * 4,
      height: bounds[3].toDouble() * 4,
      rotation: angle,
      label: '${t['label']}',
      surface: const {'type': 'rect'},
      style: {
        'label': {'weight': 700, 'size': tableLabelSize},
      },
      seating: const TableSeating(
        width: 112,
        height: 112,
        gap: 24,
        spacing: 16,
        edgePadding: 0,
      ).record,
    );
    nodes.add(table);
    for (final raw in t['seats'] as List) {
      final s = raw as List,
          wx = (raw[0] as num).toDouble() - x,
          wy = (raw[1] as num).toDouble() - y;
      final dx = wx * math.cos(a) + wy * math.sin(a),
          dy = -wx * math.sin(a) + wy * math.cos(a);
      final rotation = (s[3] as num).toDouble();
      seat(dx, dy, 28, 28, s[2] as String, rotation, parent: table.id);
      attachments.add({
        'seatId': nodes.last.id,
        'targetId': table.id,
        'placement': {'mode': 'free'},
        'rotationMode': 'manual',
      });
    }
  }

  void table(
    Map t,
    double sw,
    double sh, {
    bool lipoltice = false,
    double minSide = 0,
  }) {
    final source = (t['bounds'] as List).cast<num>();
    var x = (source[0] + source[2] / 2).toDouble(),
        y = (source[1] + source[3] / 2).toDouble();
    var w = math.max(source[2].toDouble(), minSide),
        h = math.max(source[3].toDouble(), minSide);
    final angle = (t['rotation'] as num? ?? 0).toDouble(),
        a = angle * math.pi / 180;
    final byEdge = List.generate(4, (_) => <List>[]);
    for (final raw in t['seats'] as List) {
      final seat = raw as List;
      final rotation = (seat[3] as num).toDouble();
      final edge = rotation == 180
          ? 0
          : rotation == 270
          ? 1
          : rotation == 90
          ? 3
          : 2;
      byEdge[edge].add(seat);
    }
    var counts = byEdge.map((s) => s.length).toList();
    if (lipoltice) {
      if (h > w) {
        w = 16;
        h = source[3].toDouble() - 15;
        y = source[1].toDouble() + 1 + h / 2;
        if (counts.reduce((a, b) => a + b).isOdd) {
          // The last spreadsheet cell denotes a single chair at the free head.
          final side = (counts.reduce((a, b) => a + b) - 1) ~/ 2;
          counts = [0, side, 1, side];
        } else {
          counts[2] = 1;
        }
      } else {
        h = 16;
      }
    }
    // Fit ordinary chairs to the real side lengths, rather than pinning them
    // to pixels outside the physical capacity of the native tabletop.
    final horizontal = math.max(counts[0], counts[2]),
        vertical = math.max(counts[1], counts[3]);
    const spacing = 1.0;
    if (horizontal > 0) {
      sw = math.min(sw, (w + spacing) / horizontal - spacing - .05);
    }
    if (vertical > 0) {
      sw = math.min(sw, (h + spacing) / vertical - spacing - .05);
    }
    sh = math.min(sh, sw);
    final label = '${t['label']}';
    var d = tableLayout(
      shape: 'roundedRect',
      x: x * 4,
      y: y * 4,
      width: w * 4,
      height: h * 4,
      count: counts.reduce((a, b) => a + b),
      edgeCounts: counts,
      seating: TableSeating(
        width: sw * 4,
        height: sh * 4,
        gap: 4,
        spacing: spacing * 4,
        edgePadding: 0,
      ),
    );
    final root = d.nodes.firstWhere((n) => n.kind == 'table');
    final rootId = root.id;
    // Keep original seat numbers in their order along each edge. Lipoltice
    // and Lucerna have no published seat numbering, so leave their places blank.
    for (var edge = 0; edge < 4; edge++) {
      double along(List s) {
        final dx = (s[0] as num).toDouble() - x,
            dy = (s[1] as num).toDouble() - y;
        return edge.isEven
            ? dx * math.cos(a) + dy * math.sin(a)
            : -dx * math.sin(a) + dy * math.cos(a);
      }

      byEdge[edge].sort((a, b) => along(a).compareTo(along(b)));
    }
    final edgeNames = ['top', 'right', 'bottom', 'left'];
    final labels = <String, String>{};
    for (var edge = 0; edge < 4; edge++) {
      final slots =
          d.nodes
              .where(
                (n) =>
                    n.kind == 'seat' &&
                    tableSideForSeat(d, n) == edgeNames[edge],
              )
              .toList()
            ..sort(
              (a, b) =>
                  (edge.isEven ? a.x : a.y).compareTo(edge.isEven ? b.x : b.y),
            );
      for (var i = 0; i < slots.length; i++) {
        labels[slots[i].id] = i < byEdge[edge].length
            ? byEdge[edge][i][2] as String
            : '';
      }
    }
    final size = tableLabelSize;
    d = d.copyWith(
      nodes: d.nodes
          .map(
            (n) => n.id == rootId
                ? n.copyWith(
                    rotation: angle,
                    label: label,
                    style: {
                      ...n.style,
                      'label': {'size': size, 'weight': 700},
                    },
                  )
                : n.kind == 'seat'
                ? n.copyWith(label: labels[n.id] ?? '')
                : n,
          )
          .toList(),
    );
    nodes.addAll(d.nodes);
    attachments.addAll(d.attachments);
  }

  void section(String title, {int first = 0}) {
    final root = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      width: 1,
      height: 1,
      label: title,
    );
    for (var i = first; i < nodes.length; i++) {
      if (nodes[i].parentId == null) {
        nodes[i] = nodes[i].copyWith(parentId: root.id);
      }
    }
    nodes.add(root);
    sections.add({
      'id': newLayoutId(),
      'title': title,
      'rootId': root.id,
      'levelId': title,
    });
  }

  VenueLayoutDocument finish() => VenueLayoutDocument(
    nodes: nodes,
    attachments: attachments,
    sections: sections,
    canvas: {
      'x': 0,
      'y': 0,
      'width': width * 4,
      'height': height * 4,
      'fill': '#FFFFFFFF',
    },
    styles: {
      'label': {
        'size': 64,
        'weight': 700,
        'color': '#243530FF',
        'align': 'center',
      },
    },
  );
}
