import 'dart:math';
import 'model.dart';

typedef ScenePath = List<List<dynamic>>;

/// Closed polygon contour with locally bounded corner fillets. Authored
/// vertices remain unchanged; both renderers and hit contours use this path.
ScenePath polygonContourPath(List points, {double cornerRadius = 0}) {
  if (cornerRadius <= 0 || points.length < 3) {
    return [
      for (var i = 0; i < points.length; i++)
        [i == 0 ? 'M' : 'L', ...(points[i] as List)],
      ['Z'],
    ];
  }
  final entries = <List<double>>[], exits = <List<double>>[];
  for (var i = 0; i < points.length; i++) {
    final a = points[(i + points.length - 1) % points.length] as List,
        b = points[i] as List,
        c = points[(i + 1) % points.length] as List;
    final ux = (a[0] as num) - (b[0] as num),
        uy = (a[1] as num) - (b[1] as num),
        vx = (c[0] as num) - (b[0] as num),
        vy = (c[1] as num) - (b[1] as num);
    final ul = sqrt(ux * ux + uy * uy), vl = sqrt(vx * vx + vy * vy);
    final cosine = ul * vl < 1e-12
        ? -1.0
        : ((ux * vx + uy * vy) / (ul * vl)).clamp(-1.0, 1.0);
    final tangent = tan(acos(cosine) / 2);
    final distance = ul < .0001 || vl < .0001 || tangent.abs() < .0001
        ? 0.0
        : min(cornerRadius / tangent, min(ul, vl) / 2);
    entries.add([
      (b[0] as num).toDouble() + (ul == 0 ? 0 : ux / ul * distance),
      (b[1] as num).toDouble() + (ul == 0 ? 0 : uy / ul * distance),
    ]);
    exits.add([
      (b[0] as num).toDouble() + (vl == 0 ? 0 : vx / vl * distance),
      (b[1] as num).toDouble() + (vl == 0 ? 0 : vy / vl * distance),
    ]);
  }
  return [
    ['M', ...entries.first],
    for (var i = 0; i < points.length; i++) ...[
      if (i > 0) ['L', ...entries[i]],
      ['Q', ...(points[i] as List), ...exits[i]],
    ],
    ['Z'],
  ];
}

/// Canonical visual outline shared by both renderers and the hit index.
/// Collision/resize footprints remain the authored width/height hull.
ScenePath nodePath(LayoutNode n, {LayoutNode? parent}) {
  if (n.surface != null) {
    n = n.copyWith(properties: surfaceGeometryProperties(n));
  }
  final styled = _chairContours(n, parent);
  if (styled != null) return contoursPath(styled);
  final w = quantize(n.width) / 2,
      h = quantize(n.height) / 2,
      p = n.properties,
      shape = p['shape'] ?? (n.kind == 'seat' ? 'roundedRect' : 'rect');
  if (const ['circle', 'ellipse', 'oval', 'round'].contains(shape)) {
    const k = 0.5522847498307936;
    return [
      ['M', w, 0],
      ['C', w, h * k, w * k, h, 0, h],
      ['C', -w * k, h, -w, h * k, -w, 0],
      ['C', -w, -h * k, -w * k, -h, 0, -h],
      ['C', w * k, -h, w, -h * k, w, 0],
      ['Z'],
    ];
  }
  if (const ['polygon', 'polyline', 'line', 'arrow'].contains(shape)) {
    final points =
        p['points'] as List? ??
        [
          [-w, 0],
          [w, 0],
        ];
    final radius = (p['cornerRadius'] as num? ?? (n.kind == 'table' ? 6 : 0))
        .toDouble();
    final result = shape == 'polygon'
        ? polygonContourPath(points, cornerRadius: radius)
        : <List<dynamic>>[
            for (var i = 0; i < points.length; i++)
              [i == 0 ? 'M' : 'L', ...(points[i] as List)],
          ];
    if (shape == 'polygon') {
      for (final hole in p['holes'] as List? ?? const []) {
        result.addAll(polygonContourPath(hole as List, cornerRadius: radius));
      }
    }
    if (shape == 'arrow' && points.length >= 2) {
      final headLength = (p['arrowHeadLength'] as num? ?? 12).toDouble();
      final a = points[points.length - 2] as List,
          b = points.last as List,
          angle = atan2(
            (b[1] as num) - (a[1] as num),
            (b[0] as num) - (a[0] as num),
          );
      result.addAll([
        [
          'M',
          b[0] - headLength * cos(angle - 0.5),
          b[1] - headLength * sin(angle - 0.5),
        ],
        ['L', b[0], b[1]],
        [
          'L',
          b[0] - headLength * cos(angle + 0.5),
          b[1] - headLength * sin(angle + 0.5),
        ],
      ]);
    }
    return result;
  }
  final r = min(
    min(w, h),
    (p['cornerRadius'] as num? ??
            (shape == 'roundedRect' ||
                    (n.kind == 'table' &&
                        const ['rect', 'rectangle'].contains(shape))
                ? 6
                : 0))
        .toDouble(),
  );
  return r <= 0
      ? [
          ['M', -w, -h],
          ['L', w, -h],
          ['L', w, h],
          ['L', -w, h],
          ['Z'],
        ]
      : [
          ['M', -w + r, -h],
          ['L', w - r, -h],
          ['Q', w, -h, w, -h + r],
          ['L', w, h - r],
          ['Q', w, h, w - r, h],
          ['L', -w + r, h],
          ['Q', -w, h, -w, h - r],
          ['L', -w, -h + r],
          ['Q', -w, -h, -w + r, -h],
          ['Z'],
        ];
}

String chairStyle(LayoutNode node) =>
    node.properties['seatStyle'] as String? ??
    switch (node.properties['material']) {
      'wood' || 'hall' => 'wood',
      'lounge' => 'upholstered',
      'round' => 'round',
      'banquet' => 'banquet',
      'transit' => 'transit',
      _ => 'plain',
    };

bool _cushion(LayoutNode node, LayoutNode? parent) =>
    node.properties['furniture'] == 'cushion' ||
    parent?.kind == 'furniture' && parent?.properties['furniture'] == 'couch';

List<List<List<double>>>? _chairContours(LayoutNode node, LayoutNode? parent) {
  if (isStoolNode(node, parent: parent)) {
    final w = quantize(node.width) / 2, h = quantize(node.height) / 2;
    final style = chairStyle(node);
    return [
      if (style == 'wood') ...woodStoolFrame(node),
      _ellipse(
        w *
            (style == 'wood'
                ? 0.79
                : style == 'upholstered'
                ? 0.98
                : 0.90),
        h *
            (style == 'wood'
                ? 0.79
                : style == 'upholstered'
                ? 0.98
                : 0.90),
      ),
    ];
  }
  if (node.kind == 'seat' && _cushion(node, parent)) {
    if ((node.properties['material'] ?? parent?.properties['material']) ==
        'lounge') {
      final w = quantize(node.width) * .42, h = quantize(node.height) * .42;
      // Inset pillowy cushions leave the lounge's thicker arms/back visible;
      // authored cushion bounds, IDs, spacing and upholstery count stay intact.
      return [
        [
          for (var i = 0; i < 32; i++)
            (() {
              final c = cos(i * 2 * pi / 32), s = sin(i * 2 * pi / 32);
              return [
                quantize(w * c.sign * pow(c.abs(), .55)),
                quantize(h * s.sign * pow(s.abs(), .55)),
              ];
            })(),
        ],
      ];
    }
    return null;
  }
  if (node.kind != 'seat' ||
      const [
        'polygon',
        'polyline',
        'line',
        'arrow',
      ].contains(node.properties['shape'])) {
    return null;
  }
  final style = chairStyle(node);
  if (style == 'plain') return null;
  final w = quantize(node.width) / 2, h = quantize(node.height) / 2;
  if (style == 'round') {
    return [_ellipse(w, h)];
  }
  final contours = style == 'transit'
      ? <List<List<double>>>[
          [
            [-.72 * w, -.94 * h],
            [.72 * w, -.94 * h],
            [.84 * w, -.70 * h],
            [.78 * w, .42 * h],
            [-.78 * w, .42 * h],
            [-.84 * w, -.70 * h],
          ],
          [
            [-.84 * w, .50 * h],
            [.84 * w, .50 * h],
            [.90 * w, .82 * h],
            [.70 * w, .98 * h],
            [-.70 * w, .98 * h],
            [-.90 * w, .82 * h],
          ],
          [
            [-.98 * w, -.10 * h],
            [-.82 * w, -.10 * h],
            [-.82 * w, .65 * h],
            [-.98 * w, .65 * h],
          ],
          [
            [.82 * w, -.10 * h],
            [.98 * w, -.10 * h],
            [.98 * w, .65 * h],
            [.82 * w, .65 * h],
          ],
        ]
      : style == 'banquet'
      ? <List<List<double>>>[
          // A compact banquet chair: tapered padded seat, two uprights and
          // a separate bowed back rail. No lounge arms or circular cushion.
          [
            [-.72 * w, -.92 * h],
            [.72 * w, -.92 * h],
            [.86 * w, -.78 * h],
            [.76 * w, .34 * h],
            [.64 * w, .46 * h],
            [-.64 * w, .46 * h],
            [-.76 * w, .34 * h],
            [-.86 * w, -.78 * h],
          ],
          [
            [-.72 * w, .30 * h],
            [-.54 * w, .30 * h],
            [-.54 * w, .72 * h],
            [-.72 * w, .72 * h],
          ],
          [
            [.54 * w, .30 * h],
            [.72 * w, .30 * h],
            [.72 * w, .72 * h],
            [.54 * w, .72 * h],
          ],
          [
            [-.78 * w, .58 * h],
            [.78 * w, .58 * h],
            [.88 * w, .74 * h],
            [.82 * w, .92 * h],
            [.64 * w, h],
            [-.64 * w, h],
            [-.82 * w, .92 * h],
            [-.88 * w, .74 * h],
          ],
        ]
      : style == 'wood'
      ? <List<List<double>>>[
          ...woodChairFrame(node),
          _chairRoundedRect(-.86 * w, -h, .86 * w, .42 * h, min(w, h) * .12),
        ]
      : <List<List<double>>>[
          if (style == 'roundUpholstered')
            _ellipse(w * .80, h * .80, cy: -.20 * h)
          else
            _chairRoundedRect(-.90 * w, -h, .90 * w, .44 * h, min(w, h) * .38),
          ..._upholsteredBackrest(node),
        ];
  return [
    for (final contour in contours)
      [
        for (final point in contour) [quantize(point[0]), quantize(point[1])],
      ],
  ];
}

/// Stitch seam inset into the tapered banquet seat, sharing its orientation.
ScenePath banquetChairInlay(LayoutNode node, {LayoutNode? parent}) {
  final w = node.width / 2, h = node.height / 2;
  return polygonContourPath([
    for (final p in <List<double>>[
      [-.58 * w, -.68 * h],
      [.58 * w, -.68 * h],
      [.52 * w, .20 * h],
      [-.52 * w, .20 * h],
    ])
      [quantize(p[0]), quantize(p[1])],
  ], cornerRadius: min(w, h) * .12);
}

/// A single wooden backrest. Small legs, posts and joints are intentionally
/// omitted so the plan stays readable at ordinary venue zoom levels.
List<List<List<double>>> woodChairFrame(LayoutNode node, {LayoutNode? parent}) {
  final w = quantize(node.width) / 2, h = quantize(node.height) / 2;
  return [
    [
      for (final point in _chairRoundedRect(
        -.94 * w,
        .60 * h,
        .94 * w,
        .96 * h,
        min(w, h) * .10,
      ))
        [quantize(point[0]), quantize(point[1])],
    ],
  ];
}

List<List<List<double>>> _upholsteredBackrest(LayoutNode node) {
  final w = node.width / 2, h = node.height / 2;
  if (chairStyle(node) == 'roundUpholstered') {
    // Cushion and shell share normalized elliptical geometry. Both authored
    // dimensions scale the complete chair, including its rounded end caps.
    final cy = -.20 * h, start = -pi / 12, end = pi * 13 / 12;
    List<double> arc(double radius, double angle) => [
      w * radius * cos(angle),
      cy + h * radius * sin(angle),
    ];
    List<double> cap(double angle, double offset) => [
      w * (.91 * cos(angle) + .09 * cos(angle + offset)),
      cy + h * (.91 * sin(angle) + .09 * sin(angle + offset)),
    ];
    return [
      [
        for (var i = 0; i <= 24; i++) arc(1, start + (end - start) * i / 24),
        for (var i = 1; i <= 6; i++) cap(end, pi * i / 6),
        for (var i = 23; i >= 0; i--) arc(.82, start + (end - start) * i / 24),
        for (var i = 1; i < 6; i++) cap(start, pi + pi * i / 6),
      ],
    ];
  }
  return [_chairRoundedRect(-w, .58 * h, w, .98 * h, min(w, h) * .18)];
}

/// Shares the same simple backrest as the body and hit outline; no inset ring.
ScenePath upholsteredChairBackrest(LayoutNode node, {LayoutNode? parent}) {
  return contoursPath([
    for (final contour in _upholsteredBackrest(node))
      [
        for (final point in contour) [quantize(point[0]), quantize(point[1])],
      ],
  ]);
}

List<List<double>> _chairRoundedRect(
  double left,
  double top,
  double right,
  double bottom,
  double radius,
) {
  final r = min(radius, min(right - left, bottom - top) / 2);
  return [
    for (final corner in [
      [right - r, top + r, -pi / 2],
      [right - r, bottom - r, 0.0],
      [left + r, bottom - r, pi / 2],
      [left + r, top + r, pi],
    ])
      for (var i = 0; i <= 4; i++)
        [
          corner[0] + r * cos(corner[2] + i * pi / 8),
          corner[1] + r * sin(corner[2] + i * pi / 8),
        ],
  ];
}

List<List<double>> _ellipse(
  double rx,
  double ry, {
  double cx = 0,
  double cy = 0,
}) => [
  for (var i = 0; i < 32; i++)
    [
      quantize(cx + rx * cos(i * 2 * pi / 32)),
      quantize(cy + ry * sin(i * 2 * pi / 32)),
    ],
];

ScenePath contoursPath(List<List<List<double>>> contours) {
  final path = <List<dynamic>>[];
  for (final original in contours) {
    var area = 0.0;
    for (var i = 0; i < original.length; i++) {
      final a = original[i], b = original[(i + 1) % original.length];
      area += a[0] * b[1] - b[0] * a[1];
    }
    final contour = area < 0 ? original.reversed.toList() : original;
    for (var i = 0; i < contour.length; i++) {
      path.add([i == 0 ? 'M' : 'L', ...contour[i]]);
    }
    path.add(['Z']);
  }
  return path;
}

/// Closed contours derived from the SAME outline commands used by renderers.
/// Curves use a fixed deterministic subdivision; style polygons remain exact.
List<List<List<double>>> nodeOutlineContours(
  LayoutNode node, {
  LayoutNode? parent,
}) {
  final path = nodePath(node, parent: parent), out = <List<List<double>>>[];
  var contour = <List<double>>[], current = <double>[0, 0];
  for (final command in path) {
    final op = command.first;
    if (op == 'M') {
      contour = [
        [(command[1] as num).toDouble(), (command[2] as num).toDouble()],
      ];
      current = contour.last;
    } else if (op == 'L') {
      current = [
        (command[1] as num).toDouble(),
        (command[2] as num).toDouble(),
      ];
      contour.add(current);
    } else if (op == 'Q' || op == 'C') {
      final start = current;
      for (var i = 1; i <= 24; i++) {
        final t = i / 24, u = 1 - t;
        current = op == 'Q'
            ? [
                u * u * start[0] +
                    2 * u * t * (command[1] as num) +
                    t * t * (command[3] as num),
                u * u * start[1] +
                    2 * u * t * (command[2] as num) +
                    t * t * (command[4] as num),
              ]
            : [
                u * u * u * start[0] +
                    3 * u * u * t * (command[1] as num) +
                    3 * u * t * t * (command[3] as num) +
                    t * t * t * (command[5] as num),
                u * u * u * start[1] +
                    3 * u * u * t * (command[2] as num) +
                    3 * u * t * t * (command[4] as num) +
                    t * t * t * (command[6] as num),
              ];
        contour.add(current);
      }
    } else if (op == 'Z') {
      if (contour.length >= 3) out.add(contour);
      contour = [];
    }
  }
  return out;
}

List<List<List<double>>> woodStoolFrame(LayoutNode node) {
  final w = quantize(node.width) / 2, h = quantize(node.height) / 2;
  return [
    for (final sx in [-1.0, 1.0])
      for (final sy in [-1.0, 1.0])
        [
          [quantize(sx * .48 * w), quantize(sy * .48 * h)],
          [quantize(sx * .88 * w), quantize(sy * .66 * h)],
          [quantize(sx * .88 * w), quantize(sy * .88 * h)],
          [quantize(sx * .66 * w), quantize(sy * .88 * h)],
        ],
  ];
}
