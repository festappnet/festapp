import 'dart:math';
import 'model.dart';
import 'table_seating.dart';
import 'geometry.dart';
import 'grid_surface.dart';

/// Editable footprints use the same polygon contract as ordinary vector shapes.
List<List<double>> surfacePresetPoints(
  String shape,
  double width,
  double height,
) {
  final l = -width / 2, r = width / 2, t = -height / 2, b = height / 2;
  final arm = min(width, height) * .28;
  return switch (shape) {
    'L' => [
      [l, t],
      [r, t],
      [r, t + arm],
      [l + arm, t + arm],
      [l + arm, b],
      [l, b],
    ],
    'U' => [
      [l, t],
      [r, t],
      [r, b],
      [r - arm, b],
      [r - arm, t + arm],
      [l + arm, t + arm],
      [l + arm, b],
      [l, b],
    ],
    'rectangle' => [
      [l, t],
      [r, t],
      [r, b],
      [l, b],
    ],
    _ => throw ArgumentError('Unknown surface footprint'),
  };
}

final _slots = Expando<List<Map<String, dynamic>>>();

/// Safe, evenly spaced positions on each edge, with clearance at corners and
/// concave recesses. The immutable node owns this bounded cache.
List<Map<String, dynamic>> polygonSurfaceSlots(LayoutNode table) =>
    _slots[table] ??= _polygonSlots(table);
List<Map<String, dynamic>> _polygonSlots(LayoutNode table) {
  final seating = TableSeating.fromTable(table),
      pitch = seating.pitch,
      offset = seating.offset;
  final polygon = localHull(table);
  if (polygon.length < 3 || polygonSelfIntersects(polygon)) return [];
  var area = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    area += a[0] * b[1] - b[0] * a[1];
  }
  final result = <Map<String, dynamic>>[], hulls = <List<List<double>>>[];
  var distance = 0.0;
  final total = List.generate(polygon.length, (i) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    return sqrt(pow(b[0] - a[0], 2) + pow(b[1] - a[1], 2));
  }).fold<double>(0, (a, b) => a + b);
  for (var edge = 0; edge < polygon.length; edge++) {
    final a = polygon[edge],
        b = polygon[(edge + 1) % polygon.length],
        dx = b[0] - a[0],
        dy = b[1] - a[1],
        length = sqrt(dx * dx + dy * dy);
    if (length < seating.width + seating.edgePadding * 2) {
      distance += length;
      continue;
    }
    final nx = (area > 0 ? dy : -dy) / length,
        ny = (area > 0 ? -dx : dx) / length;
    final cells = min(
      512,
      ((length -
                  seating.edgePadding * 2 +
                  (seating.edgePadding == 0 ? seating.spacing : 0)) /
              pitch)
          .floor(),
    );
    for (var i = 0; i < cells && result.length < 512; i++) {
      final along = (i + .5) / cells;
      final x = a[0] + along * dx + offset * nx,
          y = a[1] + along * dy + offset * ny;
      final rotation = atan2(ny, nx) * 180 / pi - 90;
      final chair = LayoutNode(
        id: table.id,
        kind: 'seat',
        x: x,
        y: y,
        width: seating.width,
        height: seating.height,
        rotation: rotation,
      );
      final hull = worldHull(chair, localMatrix(chair));
      if (polygonsOverlap(polygon, hull) ||
          hulls.any((h) => polygonsOverlap(h, hull))) {
        continue;
      }
      if (result.any(
        (s) =>
            pow(x - (s['x'] as num), 2) + pow(y - (s['y'] as num), 2) <
            pitch * pitch - .01,
      )) {
        continue;
      }
      result.add({
        'x': quantize(x),
        'y': quantize(y),
        'rotation': quantize(rotation),
        'kind': 'perimeter',
        't': (distance + along * length) / total,
      });
      hulls.add(hull);
    }
    distance += length;
  }
  return List.unmodifiable(result);
}

/// Expands a sketched centreline into an editable, closed surface. Bounded
/// mitres keep near-reversals from producing an arbitrarily long spike.
LayoutNode sketchSurface(
  List<List<double>> centerline, {
  double breadth = 100,
  bool bar = false,
  String? id,
}) {
  if (!breadth.isFinite ||
      breadth < 24 ||
      breadth > 400 ||
      centerline.length < 2 ||
      centerline.length > 128) {
    throw ArgumentError('Invalid surface sketch or width');
  }
  final normals = <List<double>>[];
  for (var i = 1; i < centerline.length; i++) {
    final a = centerline[i - 1],
        b = centerline[i],
        dx = b[0] - a[0],
        dy = b[1] - a[1],
        length = sqrt(dx * dx + dy * dy);
    if (!length.isFinite || length < 1) {
      throw ArgumentError('Sketch points must be distinct');
    }
    normals.add([-dy / length, dx / length]);
  }
  final left = <List<double>>[], right = <List<double>>[];
  for (var i = 0; i < centerline.length; i++) {
    final a = normals[max(0, i - 1)], b = normals[min(i, normals.length - 1)];
    var nx = a[0] + b[0], ny = a[1] + b[1];
    final length = sqrt(nx * nx + ny * ny);
    if (length < .1) {
      throw StateError('The surface outline cannot cross itself.');
    }
    nx /= length;
    ny /= length;
    final dot = nx * b[0] + ny * b[1];
    if (dot < .25) throw StateError('The surface outline cannot cross itself.');
    final offset = breadth / 2 / dot;
    final p = centerline[i];
    left.add([p[0] + nx * offset, p[1] + ny * offset]);
    right.add([p[0] - nx * offset, p[1] - ny * offset]);
  }
  final points = [...left, ...right.reversed];
  if (polygonSelfIntersects(points)) {
    throw StateError('The surface outline cannot cross itself.');
  }
  {
    final outline = shapeFromPoints('polygon', points, id: id);
    final geometry = outline.copyWith(
      kind: 'table',
      properties: {
        'shape': 'polygon',
        'points': outline.properties['points'],
        if (bar) ...{'furniture': 'bar', 'guestSide': 'bottom'},
      },
    );
    final brush = GridSurfaceBrush.fromNode(geometry, snap: true);
    return gridSurfaceReplacement(
      geometry.copyWith(
        surface: const {'type': 'rect'},
        seating: const TableSeating().record,
        properties: bar
            ? const {'furniture': 'bar', 'guestSide': 'bottom'}
            : const {},
      ),
      brush,
    );
  }
}
