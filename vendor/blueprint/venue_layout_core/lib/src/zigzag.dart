import 'dart:math' as math;

import 'geometry.dart';
import 'model.dart';

bool isZigzagNode(LayoutNode node) =>
    node.kind == 'shape' &&
    node.properties['shape'] == 'polyline' &&
    node.properties['pathPattern'] == 'zigzag';

/// Two alternating peaks per tooth, half-pitch terminal segments and exact
/// baseline endpoints. Coordinates are in the document frame for a new node.
LayoutNode zigzagLine(
  double startX,
  double startY,
  double endX,
  double endY, {
  int teeth = 8,
  double amplitude = 12,
  String? id,
  Map<String, dynamic> properties = const {},
  Map<String, dynamic>? style,
}) => shapeFromPoints(
  'polyline',
  _points([startX, startY], [endX, endY], teeth, amplitude),
  id: id,
  style:
      style ??
      const {'fill': '#00000000', 'stroke': '#334155FF', 'strokeWidth': 2},
  properties: {
    ...properties,
    'pathPattern': 'zigzag',
    'zigzagTeeth': teeth,
    'zigzagAmplitude': amplitude,
  },
);

/// Optional endpoints are in the node's CURRENT LOCAL frame. Recentring keeps
/// every specified/unchanged endpoint fixed in world space, including parents.
VenueLayoutDocument updateZigzag(
  VenueLayoutDocument document,
  String id, {
  int? teeth,
  double? amplitude,
  List<double>? start,
  List<double>? end,
}) {
  final node = document.nodes.firstWhere((n) => n.id == id);
  if (!isZigzagNode(node)) throw ArgumentError('Expected a zigzag line');
  final index = {for (final n in document.nodes) n.id: n};
  for (final candidate in document.nodes) {
    var current = candidate;
    final visited = <String>{};
    while (visited.add(current.id)) {
      if (current.id == id) {
        if (candidate.locked) throw StateError('Locked path object');
        break;
      }
      final parent = index[current.parentId];
      if (parent == null) break;
      current = parent;
    }
  }
  LayoutNode? ancestor = node;
  final visited = <String>{};
  while (ancestor != null && visited.add(ancestor.id)) {
    if (ancestor.locked) throw StateError('Locked path object');
    ancestor = index[ancestor.parentId];
  }
  final old = node.properties['points'] as List;
  final first =
      start ??
      (old.first as List).cast<num>().map((n) => n.toDouble()).toList();
  final last =
      end ?? (old.last as List).cast<num>().map((n) => n.toDouble()).toList();
  final count = teeth ?? node.properties['zigzagTeeth'] as int;
  final size =
      amplitude ?? (node.properties['zigzagAmplitude'] as num).toDouble();
  final normalized = shapeFromPoints(
    'polyline',
    _points(first, last, count, size),
    id: id,
    properties: {
      ...node.properties,
      'zigzagTeeth': count,
      'zigzagAmplitude': size,
    },
  );
  final angle = quantize(node.rotation) * math.pi / 180;
  final updated = node.copyWith(
    x: node.x + normalized.x * math.cos(angle) - normalized.y * math.sin(angle),
    y: node.y + normalized.x * math.sin(angle) + normalized.y * math.cos(angle),
    width: normalized.width,
    height: normalized.height,
    properties: normalized.properties,
  );
  final candidate = document.copyWith(
    nodes: [for (final n in document.nodes) n.id == id ? updated : n],
  );
  // Correct recentering in the canonical quantized world matrix frame.
  final target = transformPoint(
    worldMatrix(document, node),
    first[0],
    first[1],
  );
  final localTarget = transformPoint(
    inverseMatrix(worldMatrix(candidate, updated)),
    target[0],
    target[1],
  );
  final vertices = normalized.properties['points'] as List;
  final shiftX = localTarget[0] - (vertices.first[0] as num),
      shiftY = localTarget[1] - (vertices.first[1] as num);
  final corrected = updated.copyWith(
    properties: {
      ...updated.properties,
      'points': [
        for (final p in vertices)
          [quantize((p[0] as num) + shiftX), quantize((p[1] as num) + shiftY)],
      ],
    },
  );
  final result = document.copyWith(
    nodes: [for (final n in document.nodes) n.id == id ? corrected : n],
  );
  final issues = validateDocument(result);
  if (issues.isNotEmpty)
    throw StateError(
      'Invalid zigzag: ${issues.map((e) => e.reason).join(', ')}',
    );
  return result;
}

/// A rectangular resize scales baseline endpoints and perpendicular amplitude,
/// then regenerates regular peaks rather than shearing the authored pattern.
VenueLayoutDocument resizeZigzagLine(
  VenueLayoutDocument d,
  String id,
  double width,
  double height,
) {
  if (!width.isFinite ||
      !height.isFinite ||
      width <= 0 ||
      height <= 0 ||
      width > layoutLimits['geometryAbsMax']! ||
      height > layoutLimits['geometryAbsMax']!) {
    throw ArgumentError(
      'Dimensions must be finite, positive and within limits',
    );
  }
  final n = d.nodes.firstWhere((n) => n.id == id);
  if (!isZigzagNode(n)) throw ArgumentError('Expected a zigzag line');
  final points = n.properties['points'] as List;
  final a = (points.first as List).cast<num>(),
      b = (points.last as List).cast<num>();
  final sx = width / n.width, sy = height / n.height;
  final dx = b[0] - a[0], dy = b[1] - a[1];
  final oldLength = math.sqrt(dx * dx + dy * dy);
  final newLength = math.sqrt(dx * dx * sx * sx + dy * dy * sy * sy);
  return updateZigzag(
    d,
    id,
    start: [a[0] * sx, a[1] * sy],
    end: [b[0] * sx, b[1] * sy],
    amplitude:
        (n.properties['zigzagAmplitude'] as num) *
        sx *
        sy *
        oldLength /
        newLength,
  );
}

List<List<double>> _points(
  List<double> a,
  List<double> b,
  int teeth,
  double amplitude,
) {
  if (teeth < 1 || 2 * teeth + 2 > layoutLimits['verticesMax']!) {
    throw RangeError.range(
      teeth,
      1,
      (layoutLimits['verticesMax']!.toInt() - 2) ~/ 2,
      'teeth',
    );
  }
  if (a.length != 2 ||
      b.length != 2 ||
      [
        ...a,
        ...b,
        amplitude,
      ].any((v) => !v.isFinite || v.abs() > layoutLimits['geometryAbsMax']!) ||
      amplitude <= 0) {
    throw ArgumentError('Invalid zigzag coordinates or amplitude');
  }
  final dx = b[0] - a[0], dy = b[1] - a[1];
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 0.001) throw ArgumentError('Zigzag endpoints must be distinct');
  final points = <List<double>>[
    [...a],
  ];
  for (var i = 0; i < 2 * teeth; i++) {
    final t = (i + 0.5) / (2 * teeth),
        offset = i.isEven ? amplitude : -amplitude;
    points.add([
      a[0] + dx * t - dy / length * offset,
      a[1] + dy * t + dx / length * offset,
    ]);
  }
  points.add([...b]);
  if (points
      .expand((p) => p)
      .any((v) => v.abs() > layoutLimits['geometryAbsMax']!)) {
    throw ArgumentError('Zigzag exceeds geometry limits');
  }
  return points;
}
