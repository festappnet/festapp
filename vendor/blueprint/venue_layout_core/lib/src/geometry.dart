import 'dart:math';

import 'model.dart';
import 'node_outline.dart';

List<double> multiplyMatrix(List<double> a, List<double> b) => [
  a[0] * b[0] + a[2] * b[1],
  a[1] * b[0] + a[3] * b[1],
  a[0] * b[2] + a[2] * b[3],
  a[1] * b[2] + a[3] * b[3],
  a[0] * b[4] + a[2] * b[5] + a[4],
  a[1] * b[4] + a[3] * b[5] + a[5],
];
List<double> transformPoint(List<double> m, double x, double y) => [
  m[0] * x + m[2] * y + m[4],
  m[1] * x + m[3] * y + m[5],
];
List<double> inverseMatrix(List<double> m) {
  final det = m[0] * m[3] - m[1] * m[2];
  if (det.abs() < 1e-12) throw ArgumentError('Singular matrix');
  return [
    m[3] / det,
    -m[1] / det,
    -m[2] / det,
    m[0] / det,
    (m[2] * m[5] - m[3] * m[4]) / det,
    (m[1] * m[4] - m[0] * m[5]) / det,
  ];
}

List<double> localMatrix(LayoutNode n) {
  final r = quantize(n.rotation) * pi / 180;
  return [cos(r), sin(r), -sin(r), cos(r), quantize(n.x), quantize(n.y)];
}

final _worldCache = Expando<Map<String, List<double>>>();
Map<String, List<double>> worldMatrices(VenueLayoutDocument d) {
  final existing = _worldCache[d];
  if (existing != null) return existing;
  final nodes = {for (final n in d.nodes) n.id: n},
      cache = <String, List<double>>{},
      visiting = <String>{};
  List<double> resolve(LayoutNode n) {
    if (cache[n.id] != null) return cache[n.id]!;
    if (!visiting.add(n.id)) throw ArgumentError('Parent cycle');
    final p = nodes[n.parentId];
    final rotation = n.rotation;
    final local = localMatrix(
      rotation == n.rotation ? n : n.copyWith(rotation: rotation),
    );
    final m = p == null ? local : multiplyMatrix(resolve(p), local);
    visiting.remove(n.id);
    return cache[n.id] = m;
  }

  for (final n in d.nodes) {
    resolve(n);
  }
  return _worldCache[d] = Map.unmodifiable(
    cache.map((id, m) => MapEntry(id, List<double>.unmodifiable(m))),
  );
}

List<double> worldMatrix(VenueLayoutDocument d, LayoutNode n) =>
    worldMatrices(d)[n.id]!.map(quantize).toList();
List<List<double>> localHull(LayoutNode n) {
  if (n.surface != null) {
    n = n.copyWith(properties: surfaceGeometryProperties(n));
  }
  final shape = n.properties['shape'];
  if (shape == 'polygon' && n.properties['points'] is List) {
    return (n.properties['points'] as List)
        .map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
        .toList();
  }
  if (shape == 'circle' ||
      shape == 'ellipse' ||
      shape == 'oval' ||
      shape == 'round') {
    return List.generate(
      64,
      (i) => [cos(i * pi / 32) * n.width / 2, sin(i * pi / 32) * n.height / 2],
    );
  }
  return [
    [-n.width / 2, -n.height / 2],
    [n.width / 2, -n.height / 2],
    [n.width / 2, n.height / 2],
    [-n.width / 2, n.height / 2],
  ];
}

Map<String, double> boundsOfPoints(List<List<double>> p) {
  if (p.isEmpty) return {'x': 0, 'y': 0, 'width': 0, 'height': 0};
  final x = p.map((e) => e[0]).reduce(min), y = p.map((e) => e[1]).reduce(min);
  return {
    'x': x,
    'y': y,
    'width': p.map((e) => e[0]).reduce(max) - x,
    'height': p.map((e) => e[1]).reduce(max) - y,
  };
}

List<List<double>> worldHull(LayoutNode n, List<double> m) =>
    localHull(n).map((p) => transformPoint(m, p[0], p[1])).toList();
Map<String, double> nodeBounds(VenueLayoutDocument d, LayoutNode n) =>
    boundsOfPoints(worldHull(n, worldMatrix(d, n)));
Map<String, double> documentBounds(VenueLayoutDocument d) {
  final m = worldMatrices(d);
  return boundsOfPoints(
    d.nodes
        .where((n) => n.kind != 'group')
        .expand((n) => worldHull(n, m[n.id]!))
        .toList(),
  );
}

bool pointInPolygon(List<List<double>> points, double x, double y) =>
    polygonRingContains(points, x, y);

int renderBand(LayoutNode n) => n.kind == 'seat'
    ? 2
    : n.kind == 'text'
    ? 3
    : 1;
// A sibling's z is authoritative; equal-z ties use kind and canonical IDs.
// A subtree is always contiguous, including all of its text and seats.
Map<String?, List<LayoutNode>> _layerSiblings(VenueLayoutDocument d) {
  final siblings = <String?, List<LayoutNode>>{};
  for (final n in d.nodes) {
    (siblings[n.parentId] ??= []).add(n);
  }
  for (final list in siblings.values) {
    list.sort((a, b) {
      final z = a.z.compareTo(b.z);
      if (z != 0) return z;
      final band = renderBand(a).compareTo(renderBand(b));
      return band != 0 ? band : a.id.compareTo(b.id);
    });
  }
  return siblings;
}

List<LayoutNode> orderedNodes(VenueLayoutDocument d) {
  final siblings = _layerSiblings(d), result = <LayoutNode>[];
  final visited = <String>{};
  void append(LayoutNode n) {
    if (!visited.add(n.id)) return;
    result.add(n);
    for (final child in siblings[n.id] ?? const <LayoutNode>[]) {
      append(child);
    }
  }

  for (final root in siblings[null] ?? const <LayoutNode>[]) {
    append(root);
  }
  return result;
}

/// Moves selected subtrees to a sibling-stack boundary without changing their
/// parent, geometry, identity, or the relative order of their descendants.
VenueLayoutDocument moveLayoutLayers(
  VenueLayoutDocument d,
  Set<String> ids, {
  required bool toFront,
}) => _moveLayoutLayers(d, ids, toFront: toFront);

/// Moves selected subtrees one position through their respective sibling stacks.
VenueLayoutDocument reorderLayoutLayers(
  VenueLayoutDocument d,
  Set<String> ids, {
  required int direction,
}) {
  if (direction != 1 && direction != -1) {
    throw ArgumentError('Direction must be +1 or -1');
  }
  return _moveLayoutLayers(d, ids, direction: direction);
}

VenueLayoutDocument _moveLayoutLayers(
  VenueLayoutDocument d,
  Set<String> ids, {
  bool? toFront,
  int? direction,
}) {
  if (ids.isEmpty) return d;
  final byId = {for (final n in d.nodes) n.id: n};
  if (ids.any((id) => !byId.containsKey(id))) {
    throw ArgumentError('Unknown layer');
  }
  final selected = <String>{};
  for (final id in ids) {
    var parent = byId[id]!.parentId;
    var covered = false;
    while (parent != null) {
      if (ids.contains(parent)) covered = true;
      parent = byId[parent]?.parentId;
    }
    if (!covered) selected.add(id);
  }
  // A locked descendant or ancestor prevents reordering the whole assembly.
  final moved = <String>{};
  for (final n in d.nodes) {
    LayoutNode? current = n;
    var included = false;
    while (current != null) {
      if (selected.contains(current.id)) included = true;
      current = byId[current.parentId];
    }
    if (included) moved.add(n.id);
  }
  for (final id in moved) {
    LayoutNode? n = byId[id];
    while (n != null) {
      if (n.locked) {
        throw StateError('Locked object ${n.label.isEmpty ? n.id : n.label}');
      }
      n = byId[n.parentId];
    }
  }
  final replacements = <String, int>{};
  for (final entry in _layerSiblings(d).entries) {
    final siblings = entry.value;
    if (!siblings.any((n) => selected.contains(n.id))) continue;
    final before = siblings.map((n) => n.id).toList();
    if (toFront != null) {
      final active = siblings.where((n) => selected.contains(n.id)).toList();
      final other = siblings.where((n) => !selected.contains(n.id)).toList();
      siblings
        ..clear()
        ..addAll(toFront ? [...other, ...active] : [...active, ...other]);
    } else if (direction! > 0) {
      for (var i = siblings.length - 2; i >= 0; i--) {
        if (selected.contains(siblings[i].id) &&
            !selected.contains(siblings[i + 1].id)) {
          final n = siblings[i];
          siblings[i] = siblings[i + 1];
          siblings[i + 1] = n;
        }
      }
    } else {
      for (var i = 1; i < siblings.length; i++) {
        if (selected.contains(siblings[i].id) &&
            !selected.contains(siblings[i - 1].id)) {
          final n = siblings[i];
          siblings[i] = siblings[i - 1];
          siblings[i - 1] = n;
        }
      }
    }
    if (List.generate(
      siblings.length,
      (i) => siblings[i].id == before[i],
    ).every((v) => v)) {
      continue;
    }
    if (toFront != null) {
      final active = siblings.where((n) => selected.contains(n.id)).toList();
      final stationary = siblings
          .where((n) => !selected.contains(n.id))
          .toList();
      if (stationary.isEmpty) continue;
      final start = toFront
          ? stationary.map((n) => n.z).reduce(max) + 1
          : stationary.map((n) => n.z).reduce(min) - active.length;
      for (var i = 0; i < active.length; i++) {
        replacements[active[i].id] = start + i;
      }
    } else {
      // This is a canonical rank reindex, not a change in the logical order
      // of unselected siblings. Locked selected assemblies were rejected above.
      for (var i = 0; i < siblings.length; i++) {
        replacements[siblings[i].id] = i;
      }
    }
  }
  if (replacements.isEmpty) return d;
  return d.copyWith(
    nodes: [
      for (final n in d.nodes)
        if (replacements.containsKey(n.id))
          n.copyWith(z: replacements[n.id])
        else
          n,
    ],
  );
}

bool _openPath(LayoutNode n) =>
    const ['line', 'polyline', 'arrow'].contains(n.properties['shape']);

List<(List<double>, List<double>)> _pathSegments(LayoutNode n) {
  final points =
      (n.properties['points'] as List?)
          ?.map((v) => (v as List).map((x) => (x as num).toDouble()).toList())
          .toList() ??
      [
        [-n.width / 2, 0.0],
        [n.width / 2, 0.0],
      ];
  final segments = <(List<double>, List<double>)>[
    for (var i = 1; i < points.length; i++) (points[i - 1], points[i]),
  ];
  if (n.properties['shape'] == 'arrow' && points.length >= 2) {
    final a = points[points.length - 2],
        b = points.last,
        angle = atan2(b[1] - a[1], b[0] - a[0]);
    // Match the two open arrowhead strokes generated by nodePath.
    for (final offset in [-.5, .5]) {
      segments.add((
        b,
        [b[0] - 12 * cos(angle + offset), b[1] - 12 * sin(angle + offset)],
      ));
    }
  }
  return segments;
}

/// Both active and blocking targets participate in resolution. The winner is
/// returned to the mode handler, which owns availability feedback and actions.
enum LayoutTapDisposition { activate, block, ignore }

class LayoutSpatialIndex {
  final VenueLayoutDocument document;
  final Map<String, List<double>> matrices;
  final Map<String, List<LayoutNode>> _cells = {};
  final List<LayoutNode> _large = [];
  final Map<String, int> _paintRanks = {};
  final Map<String, LayoutNode> _nodes = {};
  final _hitContours = <String, List<List<List<double>>>>{};
  final _hitInverse = <String, List<double>>{};
  final double cellSize;
  LayoutSpatialIndex(this.document, {this.cellSize = 128})
    : matrices = worldMatrices(document) {
    final ordered = orderedNodes(document);
    for (var i = 0; i < ordered.length; i++) {
      final n = ordered[i];
      _paintRanks[n.id] = i;
      _nodes[n.id] = n;
      if (n.kind == 'group') continue;
      final b = boundsOfPoints(
        _openPath(n)
            ? _pathSegments(n)
                  .expand((segment) => [segment.$1, segment.$2])
                  .map((p) => transformPoint(matrices[n.id]!, p[0], p[1]))
                  .toList()
            : worldHull(n, matrices[n.id]!),
      );
      if (_openPath(n)) {
        final padding = max(
          3.0,
          (effectiveNodeProperties(document, n)['strokeWidth'] as num? ?? 1) /
              2,
        );
        b['x'] = b['x']! - padding;
        b['y'] = b['y']! - padding;
        b['width'] = b['width']! + padding * 2;
        b['height'] = b['height']! + padding * 2;
      }
      final x = (b['x']! / cellSize).floor(),
          y = (b['y']! / cellSize).floor(),
          r = ((b['x']! + b['width']!) / cellSize).floor(),
          bot = ((b['y']! + b['height']!) / cellSize).floor();
      if ((r - x + 1) * (bot - y + 1) > 4096) {
        _large.add(n);
        continue;
      }
      for (var i = x; i <= r; i++) {
        for (var j = y; j <= bot; j++) {
          (_cells['$i,$j'] ??= []).add(n);
        }
      }
    }
  }

  /// [tolerance] is a world-space radius for open strokes. Editors can supply
  /// a screen-pixel radius divided by viewport zoom. Filled shapes are unchanged.
  String? hitTest(
    double x,
    double y, {
    double? tolerance,
    bool Function(LayoutNode)? accept,
  }) {
    if (tolerance != null && (!tolerance.isFinite || tolerance < 0)) {
      throw ArgumentError('Hit tolerance must be finite and nonnegative');
    }
    final radius = tolerance ?? 3;
    final candidates = radius > cellSize * 32
        ? _nodes.values.where((n) => n.kind != 'group').toList()
        : query({
            'x': x - radius,
            'y': y - radius,
            'width': radius * 2,
            'height': radius * 2,
          }).map((id) => _nodes[id]!).toList();
    candidates.sort((a, b) => _paintRanks[b.id]!.compareTo(_paintRanks[a.id]!));
    for (final n in candidates) {
      if (accept != null && !accept(n)) continue;
      final inverse = _hitInverse.putIfAbsent(
        n.id,
        () => inverseMatrix(matrices[n.id]!.map(quantize).toList()),
      );
      final p = transformPoint(inverse, x, y);
      if (_openPath(n)) {
        for (final (a, b) in _pathSegments(n)) {
          final dx = b[0] - a[0],
              dy = b[1] - a[1],
              len = dx * dx + dy * dy,
              t = len == 0
                  ? 0.0
                  : ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len;
          final v = t.clamp(0, 1);
          if (pow(p[0] - a[0] - v * dx, 2) + pow(p[1] - a[1] - v * dy, 2) <=
              pow(
                max(
                  tolerance ?? 3,
                  (effectiveNodeProperties(document, n)['strokeWidth']
                              as num? ??
                          1) /
                      2,
                ),
                2,
              )) {
            return n.properties['role'] == 'decoration' &&
                    _nodes[n.parentId]?.assembly != null
                ? n.parentId
                : n.id;
          }
        }
      } else {
        final contours = _hitContours.putIfAbsent(
          n.id,
          () => nodeOutlineContours(
            n.copyWith(properties: effectiveNodeProperties(document, n)),
            parent: _nodes[n.parentId],
          ),
        );
        if (contours.any((contour) => pointInPolygon(contour, p[0], p[1])) &&
            !(surfaceGeometryProperties(n)['holes'] as List? ?? const []).any(
              (h) => pointInPolygon(
                (h as List)
                    .map(
                      (p) => (p as List)
                          .map((n) => (n as num).toDouble())
                          .toList(),
                    )
                    .toList(),
                p[0],
                p[1],
              ),
            )) {
          return n.properties['role'] == 'decoration' &&
                  _nodes[n.parentId]?.assembly != null
              ? n.parentId
              : n.id;
        }
      }
    }
    return null;
  }

  /// Resolves a completed user tap. Exact geometry always wins over slop.
  /// The caller owns mode rules; blocking targets never fall through to others.
  String? resolveTap(
    double x,
    double y, {
    required double tolerance,
    LayoutTapDisposition Function(LayoutNode)? classify,
    String Function(String)? selectionTarget,
  }) {
    if (!tolerance.isFinite || tolerance < 0) {
      throw ArgumentError('Tap tolerance must be finite and nonnegative');
    }
    final candidates = tolerance > cellSize * 32
        ? _nodes.values.where((n) => n.kind != 'group').toList()
        : query({
            'x': x - tolerance,
            'y': y - tolerance,
            'width': tolerance * 2,
            'height': tolerance * 2,
          }).map((id) => _nodes[id]!).toList();
    candidates.sort((a, b) => _paintRanks[b.id]!.compareTo(_paintRanks[a.id]!));
    LayoutNode? winner;
    var best = double.infinity;
    for (final n in candidates) {
      final disposition = classify?.call(n) ?? LayoutTapDisposition.activate;
      if (disposition == LayoutTapDisposition.ignore) continue;
      final matrix = matrices[n.id]!;
      double segmentDistance(List<double> a, List<double> b) {
        final dx = b[0] - a[0], dy = b[1] - a[1];
        final length = dx * dx + dy * dy;
        final t = length == 0
            ? 0.0
            : (((x - a[0]) * dx + (y - a[1]) * dy) / length).clamp(0.0, 1.0);
        return sqrt(pow(x - a[0] - t * dx, 2) + pow(y - a[1] - t * dy, 2));
      }

      double ringDistance(List<List<double>> ring) {
        var distance = double.infinity;
        for (var i = 0; i < ring.length; i++) {
          distance = min(
            distance,
            segmentDistance(ring[i], ring[(i + 1) % ring.length]),
          );
        }
        return distance;
      }

      var distance = double.infinity;
      if (_openPath(n)) {
        // The document transform is rigid (nested translation/rotation only).
        // Measure from the rendered stroke, rather than its center line.
        final halfStroke =
            (effectiveNodeProperties(document, n)['strokeWidth'] as num? ?? 1) /
            2;
        for (final (a, b) in _pathSegments(n)) {
          distance = min(
            distance,
            max(
              0.0,
              segmentDistance(
                    transformPoint(matrix, a[0], a[1]),
                    transformPoint(matrix, b[0], b[1]),
                  ) -
                  halfStroke,
            ),
          );
        }
      } else {
        final contours = _hitContours.putIfAbsent(
          n.id,
          () => nodeOutlineContours(
            n.copyWith(properties: effectiveNodeProperties(document, n)),
            parent: _nodes[n.parentId],
          ),
        );
        final worldContours = contours
            .map(
              (ring) =>
                  ring.map((p) => transformPoint(matrix, p[0], p[1])).toList(),
            )
            .toList();
        final holes =
            (surfaceGeometryProperties(n)['holes'] as List? ?? const [])
                .map(
                  (h) => (h as List)
                      .map(
                        (p) => transformPoint(
                          matrix,
                          ((p as List)[0] as num).toDouble(),
                          (p[1] as num).toDouble(),
                        ),
                      )
                      .toList(),
                )
                .toList();
        final inside =
            worldContours.any((ring) => pointInPolygon(ring, x, y)) &&
            !holes.any((ring) => pointInPolygon(ring, x, y));
        distance = inside
            ? 0
            : [...worldContours, ...holes].fold<double>(
                double.infinity,
                (best, ring) => min(best, ringDistance(ring)),
              );
      }
      if (distance <= tolerance + 1e-9 && distance < best - 1e-9) {
        winner = n;
        best = distance;
        if (distance == 0) break; // candidates are already in paint order
      }
    }
    if (winner == null) return null;
    final id =
        winner.properties['role'] == 'decoration' &&
            _nodes[winner.parentId]?.assembly != null
        ? winner.parentId!
        : winner.id;
    return selectionTarget?.call(id) ?? id;
  }

  List<String> query(Map<String, double> b) {
    final result = <String>{};
    for (
      var x = (b['x']! / cellSize).floor();
      x <= ((b['x']! + b['width']!) / cellSize).floor();
      x++
    ) {
      for (
        var y = (b['y']! / cellSize).floor();
        y <= ((b['y']! + b['height']!) / cellSize).floor();
        y++
      ) {
        result.addAll((_cells['$x,$y'] ?? []).map((n) => n.id));
      }
    }
    result.addAll(_large.map((n) => n.id));
    return result.toList()..sort();
  }
}

final _indexCache = Expando<LayoutSpatialIndex>();
LayoutSpatialIndex spatialIndexFor(VenueLayoutDocument d) =>
    _indexCache[d] ??= LayoutSpatialIndex(d);
String? hitTest(
  VenueLayoutDocument d,
  double x,
  double y, {
  double? tolerance,
  bool Function(LayoutNode)? accept,
}) => spatialIndexFor(d).hitTest(x, y, tolerance: tolerance, accept: accept);
bool _convexOverlap(List<List<double>> a, List<List<double>> b) {
  for (final poly in [a, b]) {
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i],
          q = poly[(i + 1) % poly.length],
          nx = -(q[1] - p[1]),
          ny = q[0] - p[0];
      final ap = a.map((v) => v[0] * nx + v[1] * ny),
          bp = b.map((v) => v[0] * nx + v[1] * ny);
      if (ap.reduce(max) <= bp.reduce(min) + 1e-7 ||
          bp.reduce(max) <= ap.reduce(min) + 1e-7) {
        return false;
      }
    }
  }
  return true;
}

List<List<List<double>>> triangulatePolygon(List<List<double>> polygon) {
  if (polygon.length < 3) return [];
  double cross(List<double> a, List<double> b, List<double> c) =>
      (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  var area = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i], b = polygon[(i + 1) % polygon.length];
    area += a[0] * b[1] - a[1] * b[0];
  }
  final points = area < 0 ? polygon.reversed.toList() : polygon.toList(),
      result = <List<List<double>>>[];
  while (points.length > 3) {
    var clipped = false;
    for (var i = 0; i < points.length; i++) {
      final a = points[(i + points.length - 1) % points.length],
          b = points[i],
          c = points[(i + 1) % points.length];
      if (cross(a, b, c) <= 1e-9) continue;
      final contains = points.any(
        (p) =>
            !identical(p, a) &&
            !identical(p, b) &&
            !identical(p, c) &&
            cross(a, b, p) >= 0 &&
            cross(b, c, p) >= 0 &&
            cross(c, a, p) >= 0,
      );
      if (contains) continue;
      result.add([a, b, c]);
      points.removeAt(i);
      clipped = true;
      break;
    }
    if (!clipped) break;
  }
  if (points.length == 3) result.add(points);
  return result;
}

bool polygonsOverlap(List<List<double>> a, List<List<double>> b) {
  for (final ta in triangulatePolygon(a)) {
    for (final tb in triangulatePolygon(b)) {
      if (_convexOverlap(ta, tb)) return true;
    }
  }
  return false;
}

bool polygonContainsHull(List<List<double>> polygon, List<List<double>> hull) {
  if (!hull.every((p) => pointInPolygon(polygon, p[0], p[1]))) return false;
  double cross(List<double> a, List<double> b, List<double> c) =>
      (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  for (var i = 0; i < hull.length; i++) {
    for (var j = 0; j < polygon.length; j++) {
      final a = hull[i],
          b = hull[(i + 1) % hull.length],
          c = polygon[j],
          d = polygon[(j + 1) % polygon.length];
      if (cross(a, b, c) * cross(a, b, d) < -1e-9 &&
          cross(c, d, a) * cross(c, d, b) < -1e-9) {
        return false;
      }
    }
  }
  return true;
}

List<List<String>> layoutCollisions(VenueLayoutDocument d) {
  final index = LayoutSpatialIndex(d),
      nodes = {for (final n in d.nodes) n.id: n},
      out = <List<String>>[],
      seen = <String>{};
  bool physical(LayoutNode n) =>
      n.kind == 'seat' ||
      n.kind == 'table' ||
      n.kind == 'furniture' ||
      n.properties['obstacle'] == true ||
      n.properties['role'] == 'obstacle';
  for (final n in d.nodes.where(physical)) {
    final hull = worldHull(n, index.matrices[n.id]!);
    for (final id in index.query(boundsOfPoints(hull))) {
      final other = nodes[id]!;
      if (id == n.id || !physical(other)) continue;
      bool ancestor(String a, LayoutNode child) {
        var p = nodes[child.parentId];
        while (p != null) {
          if (p.id == a) return true;
          p = nodes[p.parentId];
        }
        return false;
      }

      if (ancestor(n.id, other) || ancestor(other.id, n)) continue;
      final pair = [n.id, id]..sort();
      if (!seen.add(pair.join('/'))) continue;
      if (polygonsOverlap(hull, worldHull(other, index.matrices[id]!))) {
        out.add(pair);
      }
    }
  }
  return out;
}

Map<String, dynamic> backgroundPlacement(
  double sw,
  double sh,
  Map<String, dynamic> canvas, {
  String fit = 'contain',
}) {
  if (sw <= 0 || sh <= 0) throw ArgumentError('Invalid source size');
  final w = (canvas['width'] as num).toDouble(),
      h = (canvas['height'] as num).toDouble(),
      s = fit == 'fill' ? max(w / sw, h / sh) : min(w / sw, h / sh);
  return {
    'x': (canvas['x'] as num? ?? 0) + w / 2,
    'y': (canvas['y'] as num? ?? 0) + h / 2,
    'width': sw,
    'height': sh,
    'scale': s,
    'rotation': 0,
    'opacity': 1,
    'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
  };
}

Map<String, double> selectionBounds(VenueLayoutDocument d, Set<String> ids) {
  final m = worldMatrices(d);
  final selected = {...ids};
  var changed = true;
  while (changed) {
    changed = false;
    for (final n in d.nodes) {
      if (selected.contains(n.parentId) && selected.add(n.id)) changed = true;
    }
  }
  return boundsOfPoints(
    d.nodes
        .where((n) => selected.contains(n.id) && n.kind != 'group')
        .expand((n) => worldHull(n, m[n.id]!))
        .toList(),
  );
}

Set<String> hitTestRect(
  VenueLayoutDocument d,
  Map<String, double> rect, {
  bool contained = false,
}) {
  final index = LayoutSpatialIndex(d),
      ids = index.query(rect).toSet(),
      hull = <List<double>>[
        [rect['x']!, rect['y']!],
        [rect['x']! + rect['width']!, rect['y']!],
        [rect['x']! + rect['width']!, rect['y']! + rect['height']!],
        [rect['x']!, rect['y']! + rect['height']!],
      ];
  return d.nodes
      .where(
        (n) =>
            ids.contains(n.id) &&
            n.kind != 'group' &&
            (contained
                ? worldHull(n, index.matrices[n.id]!).every(
                    (p) =>
                        p[0] >= rect['x']! &&
                        p[1] >= rect['y']! &&
                        p[0] <= rect['x']! + rect['width']! &&
                        p[1] <= rect['y']! + rect['height']!,
                  )
                : polygonsOverlap(hull, worldHull(n, index.matrices[n.id]!))),
      )
      .map((n) => n.id)
      .toSet();
}

LayoutNode shapeFromPoints(
  String shape,
  List<List<double>> points, {
  String? id,
  Map<String, dynamic> properties = const {},
  Map<String, dynamic> style = const {},
}) {
  if (points.length < 2) throw ArgumentError('At least two points required');
  final b = boundsOfPoints(points),
      cx = b['x']! + b['width']! / 2,
      cy = b['y']! + b['height']! / 2;
  return LayoutNode(
    id: id ?? newLayoutId(),
    kind: 'shape',
    style: style,
    x: cx,
    y: cy,
    width: max(1, b['width']!),
    height: max(1, b['height']!),
    properties: {
      ...properties,
      'shape': shape,
      if (properties['holes'] is List)
        'holes': [
          for (final h in properties['holes'] as List)
            [
              for (final p in h as List)
                [quantize((p[0] as num) - cx), quantize((p[1] as num) - cy)],
            ],
        ],
      'points': points
          .map((p) => [quantize(p[0] - cx), quantize(p[1] - cy)])
          .toList(),
    },
  );
}

String? nearestNode(VenueLayoutDocument d, String fromId, String direction) {
  final m = worldMatrices(d), from = m[fromId];
  if (from == null) return null;
  final v = switch (direction) {
    'left' => <double>[-1, 0],
    'right' => <double>[1, 0],
    'up' => <double>[0, -1],
    'down' => <double>[0, 1],
    _ => throw ArgumentError('Unknown direction'),
  };
  String? best;
  var score = double.infinity;
  for (final n in d.nodes) {
    if (n.id == fromId || !const ['seat', 'capacityArea'].contains(n.kind)) {
      continue;
    }
    final target = m[n.id]!,
        dx = target[4] - from[4],
        dy = target[5] - from[5],
        forward = dx * v[0] + dy * v[1];
    if (forward <= 1e-7) continue;
    final cross = (dx * v[1] - dy * v[0]).abs(),
        candidate = forward + cross * 3 + cross * cross / max(1, forward);
    if (candidate < score ||
        (candidate == score && (best == null || n.id.compareTo(best) < 0))) {
      score = candidate;
      best = n.id;
    }
  }
  return best;
}
