import 'dart:math' as math;
import 'operations.dart' show layoutSubtree, reconcileSurfaceEdit;
import 'geometry.dart';
import 'model.dart';

/// One module is a compact square table with one seat on each side.
const double tableSurfaceModuleSize = 100;

/// Counters have a shallower footprint than a four-seat table module.
const double barSurfaceModuleSize = 60;

/// Transient authoring brush. Only its compact polygon outline is persisted.
/// Shared cell edges cancel incrementally; preview cost follows the boundary.
class GridSurfaceBrush {
  GridSurfaceBrush({
    this.step = tableSurfaceModuleSize,
    this.diameter = 1,
    this.clip,
    this.originX = 0,
    this.originY = 0,
    Iterable<(int, int)> seedCells = const [],
  }) {
    if (!step.isFinite ||
        step <= 0 ||
        !originX.isFinite ||
        !originY.isFinite ||
        diameter < 1 ||
        diameter > 32)
      throw ArgumentError('Invalid brush');
    for (final cell in seedCells) {
      stampCell(cell.$1, cell.$2);
    }
  }

  /// Restores a surface in local coordinates without drawing connecting strokes.
  factory GridSurfaceBrush.fromNode(
    LayoutNode node, {
    double? width,
    double? height,
    bool snap = false,
  }) {
    final step = node.surface?['type'] == 'grid'
        ? (node.surface!['moduleSize'] as num).toDouble()
        : isBarNode(node)
        ? barSurfaceModuleSize
        : tableSurfaceModuleSize;
    final w = width ?? node.width, h = height ?? node.height;
    if (node.kind != 'table' ||
        (node.surface?['type'] != 'grid' &&
            node.properties['shape'] != 'polygon') ||
        !w.isFinite ||
        !h.isFinite ||
        w <= 0 ||
        h <= 0) {
      throw ArgumentError('Expected a custom table surface');
    }
    final targetW = math.max(step, (w / step).round() * step);
    final targetH = math.max(step, (h / step).round() * step);
    final originX = -targetW / 2, originY = -targetH / 2;
    List<List<double>> ring(List points) => [
      for (final raw in points)
        (() {
          final p = raw as List;
          final gx = ((p[0] as num) / node.width + .5) * targetW / step;
          final gy = ((p[1] as num) / node.height + .5) * targetH / step;
          if (!snap &&
              ((gx - gx.round()).abs() > .001 ||
                  (gy - gy.round()).abs() > .001 ||
                  (w - targetW).abs() > .001 ||
                  (h - targetH).abs() > .001)) {
            throw StateError('Choose a grid-aligned custom outline first.');
          }
          return [originX + gx.round() * step, originY + gy.round() * step];
        })(),
    ];
    final sourceHull = localHull(node);
    if (!snap) {
      for (var i = 0; i < sourceHull.length; i++) {
        final a = sourceHull[i], b = sourceHull[(i + 1) % sourceHull.length];
        if ((a[0] - b[0]).abs() > .001 && (a[1] - b[1]).abs() > .001) {
          throw StateError('Choose a grid-aligned custom outline first.');
        }
      }
    }
    final outer = ring(sourceHull);
    final holes = [
      for (final hole
          in surfaceGeometryProperties(node)['holes'] as List? ?? const [])
        ring(hole as List),
    ];
    final columns = (targetW / step).round(), rows = (targetH / step).round();
    if (columns * rows > 16384)
      throw StateError('Surface brush limit reached.');
    final brush = GridSurfaceBrush(
      step: step,
      originX: originX,
      originY: originY,
    );
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        final px = originX + (x + .5) * step, py = originY + (y + .5) * step;
        if (pointInPolygon(outer, px, py) &&
            !holes.any((hole) => pointInPolygon(hole, px, py))) {
          brush.stampCell(x, y);
        }
      }
    }
    // Validate connectivity and holes before this seed can replace a document.
    brush.node(id: node.id, bar: isBarNode(node));
    return brush;
  }
  final double step, originX, originY;
  final int diameter;
  final Map<String, dynamic>? clip;
  final _cells = <(int, int)>{};
  final _edges = <(int, int), Set<(int, int)>>{};
  (int, int)? _last;
  int get cellCount => _cells.length;
  Set<(int, int)> get cells => Set.unmodifiable(_cells);
  void resetStroke() => _last = null;

  /// Adds/removes exactly one module without stroke interpolation.
  bool stampCell(int x, int y, {bool erase = false}) {
    final cell = (x, y);
    if (_cells.contains(cell) == !erase) return false;
    if (!erase && _cells.length >= 16384)
      throw StateError('Surface brush limit reached.');
    if (erase) {
      _cells.remove(cell);
      edge((x + 1, y), (x, y));
      edge((x + 1, y + 1), (x + 1, y));
      edge((x, y + 1), (x + 1, y + 1));
      edge((x, y), (x, y + 1));
    } else {
      _cells.add(cell);
      edge((x, y), (x + 1, y));
      edge((x + 1, y), (x + 1, y + 1));
      edge((x + 1, y + 1), (x, y + 1));
      edge((x, y + 1), (x, y));
    }
    return true;
  }

  bool paint(double x, double y, {bool erase = false}) {
    if (!originX.isFinite ||
        !originY.isFinite ||
        !x.isFinite ||
        !y.isFinite ||
        x.abs() > layoutLimits['geometryAbsMax']! ||
        y.abs() > layoutLimits['geometryAbsMax']! ||
        step <= 0 ||
        !step.isFinite ||
        diameter < 1 ||
        diameter > 32)
      throw ArgumentError('Invalid brush');
    if (clip != null) {
      x = x.clamp(
        (clip!['x'] as num).toDouble(),
        ((clip!['x'] as num) + (clip!['width'] as num)).toDouble(),
      );
      y = y.clamp(
        (clip!['y'] as num).toDouble(),
        ((clip!['y'] as num) + (clip!['height'] as num)).toDouble(),
      );
    }
    final end = (
      ((x - originX) / step).floor(),
      ((y - originY) / step).floor(),
    );
    var at = _last ?? end;
    var changed = false;
    void stamp((int, int) p) {
      final half = diameter ~/ 2;
      for (var yy = p.$2 - half; yy < p.$2 - half + diameter; yy++)
        for (var xx = p.$1 - half; xx < p.$1 - half + diameter; xx++) {
          if (clip != null &&
              (originX + xx * step < (clip!['x'] as num) ||
                  originY + yy * step < (clip!['y'] as num) ||
                  originX + (xx + 1) * step >
                      (clip!['x'] as num) + (clip!['width'] as num) ||
                  originY + (yy + 1) * step >
                      (clip!['y'] as num) + (clip!['height'] as num)))
            continue;
          changed = stampCell(xx, yy, erase: erase) || changed;
        }
    }

    stamp(at);
    final dx = (end.$1 - at.$1).abs(),
        dy = (end.$2 - at.$2).abs(),
        sx = at.$1 < end.$1 ? 1 : -1,
        sy = at.$2 < end.$2 ? 1 : -1;
    var error = dx - dy;
    while (at != end) {
      final twice = error * 2;
      if (twice > -dy) {
        error -= dy;
        at = (at.$1 + sx, at.$2);
        stamp(at);
      }
      if (twice < dx) {
        error += dx;
        at = (at.$1, at.$2 + sy);
        stamp(at);
      }
    }
    _last = end;
    return changed;
  }

  void edge((int, int) a, (int, int) b) {
    if (_edges[b]?.remove(a) == true) {
      if (_edges[b]!.isEmpty) _edges.remove(b);
    } else {
      (_edges[a] ??= {}).add(b);
    }
  }

  LayoutNode node({required String id, bool bar = false}) {
    if (_edges.isEmpty) throw StateError('Paint inside the canvas.');
    final remaining = {
      for (final e in _edges.entries) e.key: {...e.value},
    };
    final rings = <List<List<double>>>[];
    while (remaining.isNotEmpty) {
      final start = remaining.keys.first;
      var at = start;
      (int, int)? previous;
      final vertices = <(int, int)>[];
      do {
        vertices.add(at);
        final nexts = remaining[at];
        if (nexts == null || nexts.isEmpty)
          throw StateError('Invalid painted outline');
        final candidates = nexts.toList();
        if (previous != null && candidates.length > 1) {
          final dx = at.$1 - previous.$1, dy = at.$2 - previous.$2;
          int turn((int, int) b) {
            final nx = b.$1 - at.$1, ny = b.$2 - at.$2;
            final cross = dx * ny - dy * nx;
            return cross > 0
                ? 0
                : dx * nx + dy * ny > 0
                ? 1
                : cross < 0
                ? 2
                : 3;
          }

          candidates.sort((a, b) => turn(a).compareTo(turn(b)));
        }
        final next = candidates.first;
        nexts.remove(next);
        if (nexts.isEmpty) remaining.remove(at);
        previous = at;
        at = next;
      } while (at != start && vertices.length <= 65536);
      if (at != start) throw StateError('Invalid painted outline');
      final ring = <List<double>>[];
      for (var i = 0; i < vertices.length; i++) {
        final p = vertices[(i + vertices.length - 1) % vertices.length],
            a = vertices[i],
            b = vertices[(i + 1) % vertices.length];
        if ((a.$1 - p.$1) * (b.$2 - a.$2) - (a.$2 - p.$2) * (b.$1 - a.$1) != 0)
          ring.add([originX + a.$1 * step, originY + a.$2 * step]);
      }
      if (ring.length < 3 || polygonSelfIntersects(ring))
        throw StateError('The surface outline cannot cross itself.');
      rings.add(ring);
    }
    double area(List<List<double>> ring) {
      var a = 0.0;
      for (var i = 0; i < ring.length; i++) {
        final p = ring[i], q = ring[(i + 1) % ring.length];
        a += p[0] * q[1] - q[0] * p[1];
      }
      return a;
    }

    rings.sort((a, b) => area(b).abs().compareTo(area(a).abs()));
    if (rings.skip(1).any((r) => area(r) > 0))
      throw StateError('Paint a connected surface.');
    if (rings.fold<int>(0, (s, r) => s + r.length) >
        layoutLimits['verticesMax']!)
      throw StateError('Path vertex limit reached');
    final base = shapeFromPoints(
      'polygon',
      rings.first,
      id: id,
      properties: {
        'fill': '#E2E8F0FF',
        'stroke': '#475569FF',
        'strokeWidth': 1,
        if (bar) ...{'furniture': 'bar', 'guestSide': 'bottom'},
      },
    );
    {
      final minX = rings.first.map((point) => point[0]).reduce(math.min),
          minY = rings.first.map((point) => point[1]).reduce(math.min);
      List<List<int>> gridRing(List<List<double>> ring) => [
        for (final point in ring)
          [
            ((point[0] - minX) / step).round(),
            ((point[1] - minY) / step).round(),
          ],
      ];
      final outer = gridRing(rings.first);
      final columns = outer.map((point) => point[0]).reduce(math.max),
          rows = outer.map((point) => point[1]).reduce(math.max);
      if (columns * rows > 16384)
        throw StateError('Surface brush limit reached.');
      return base.copyWith(
        kind: 'table',
        surface: {
          'type': 'grid',
          'moduleSize': step,
          'outer': outer,
          'holes': [for (final ring in rings.skip(1)) gridRing(ring)],
        },
        properties: {
          if (bar) ...{'furniture': 'bar', 'guestSide': 'bottom'},
        },
      );
    }
  }
}

/// Snaps a custom outline to the same physical modules used by painting.
LayoutNode snapTableSurfaceToGrid(
  LayoutNode node, {
  double? width,
  double? height,
  String? preset,
}) {
  if (preset != null) {
    if (!const {'L', 'rectangle'}.contains(preset))
      throw ArgumentError('Unknown grid surface preset');
    final step = isBarNode(node)
        ? barSurfaceModuleSize
        : tableSurfaceModuleSize;
    final columns = math.max(2, ((width ?? node.width) / step).ceil());
    final rows = math.max(2, ((height ?? node.height) / step).ceil());
    final brush = GridSurfaceBrush(
      step: step,
      originX: -columns * step / 2,
      originY: -rows * step / 2,
    );
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < columns; x++) {
        if (preset == 'rectangle' || x == 0 || y == rows - 1)
          brush.stampCell(x, y);
      }
    }
    return gridSurfaceReplacement(node, brush);
  }
  final brush = GridSurfaceBrush.fromNode(
    node,
    width: width,
    height: height,
    snap: true,
  );
  return gridSurfaceReplacement(node, brush);
}

/// Preserves identity, transforms, commercial metadata and appearance.
LayoutNode gridSurfaceReplacement(LayoutNode original, GridSurfaceBrush brush) {
  final shape = brush.node(id: original.id, bar: isBarNode(original));
  final angle = original.rotation * math.pi / 180;
  return original.copyWith(
    x: original.x + shape.x * math.cos(angle) - shape.y * math.sin(angle),
    y: original.y + shape.x * math.sin(angle) + shape.y * math.cos(angle),
    width: shape.width,
    height: shape.height,
    surface: shape.surface,
    properties: original.properties,
  );
}

LayoutNode _editableGridSurface(VenueLayoutDocument document, String id) {
  final subtree = layoutSubtree(document, {id});
  final byId = {for (final n in document.nodes) n.id: n};
  for (final target in subtree) {
    LayoutNode? node = byId[target];
    final seen = <String>{};
    while (node != null && seen.add(node.id)) {
      if (node.locked)
        throw StateError(
          'Locked object ${node.label.isEmpty ? node.id : node.label}',
        );
      node = byId[node.parentId];
    }
  }
  return document.nodes.firstWhere((n) => n.id == id);
}

VenueLayoutDocument resizeGridTableSurface(
  VenueLayoutDocument document,
  String id,
  double width,
  double height, {
  Set<String> protectedSeatIds = const {},
}) {
  final node = _editableGridSurface(document, id);
  final next = snapTableSurfaceToGrid(node, width: width, height: height);
  return reconcileSurfaceEdit(
    document,
    document.copyWith(
      nodes: [for (final n in document.nodes) n.id == id ? next : n],
    ),
    id,
    protectedSeatIds: protectedSeatIds,
  );
}

/// Extends or removes a module-wide strip at a boundary, using painting's cells.
VenueLayoutDocument extendGridTableSurface(
  VenueLayoutDocument document,
  String id,
  int edgeIndex,
  double x,
  double y, {
  int? cellIndex,
  Set<String> protectedSeatIds = const {},
}) {
  final node = _editableGridSurface(document, id);
  final brush = GridSurfaceBrush.fromNode(node);
  final hull = localHull(node);
  RangeError.checkValidIndex(edgeIndex, hull);
  final a = hull[edgeIndex], b = hull[(edgeIndex + 1) % hull.length];
  final dx = b[0] - a[0], dy = b[1] - a[1];
  if (dx.abs() > .001 && dy.abs() > .001)
    throw StateError('Use a grid-aligned edge.');
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < .001) return document;
  final nx = dy / length, ny = -dx / length;
  final midX = (a[0] + b[0]) / 2, midY = (a[1] + b[1]) / 2;
  final depth = (((x - midX) * nx + (y - midY) * ny) / brush.step).round();
  if (depth == 0) return document;
  // Pin the tangent to one cell of the original edge; pointer drift cannot skew it.
  if (cellIndex != null &&
      (cellIndex < 0 || cellIndex >= (length / brush.step).round())) {
    throw RangeError('Invalid boundary cell');
  }
  final tangentX = cellIndex != null
      ? a[0] + dx / length * (cellIndex + .5) * brush.step
      : dx == 0
      ? midX
      : brush.originX +
            (((midX - brush.originX) / brush.step - .00001).floor() + .5) *
                brush.step;
  final tangentY = cellIndex != null
      ? a[1] + dy / length * (cellIndex + .5) * brush.step
      : dy == 0
      ? midY
      : brush.originY +
            (((midY - brush.originY) / brush.step - .00001).floor() + .5) *
                brush.step;
  if (depth.abs() > 16384) throw StateError('Surface brush limit reached.');
  for (var i = 0; i < depth.abs(); i++) {
    final distance = (i + .5) * brush.step * depth.sign;
    final cx = ((tangentX + nx * distance - brush.originX) / brush.step)
        .floor();
    final cy = ((tangentY + ny * distance - brush.originY) / brush.step)
        .floor();
    brush.stampCell(cx, cy, erase: depth < 0);
  }
  final next = gridSurfaceReplacement(node, brush);
  return reconcileSurfaceEdit(
    document,
    document.copyWith(
      nodes: [for (final n in document.nodes) n.id == id ? next : n],
    ),
    id,
    protectedSeatIds: protectedSeatIds,
  );
}
