import 'dart:math';

import 'geometry.dart';
import 'model.dart';
import 'operations.dart' show reconcileSurfaceEdit;

/// Inserts a point after [segmentIndex] in the original local coordinate frame.
/// The final polygon segment joins its last point to its first point.
VenueLayoutDocument insertPathVertex(
  VenueLayoutDocument document,
  String id,
  int segmentIndex,
  double localX,
  double localY, {
  Set<String> protectedSeatIds = const {},
}) {
  if (!localX.isFinite ||
      !localY.isFinite ||
      localX.abs() > layoutLimits['geometryAbsMax']! ||
      localY.abs() > layoutLimits['geometryAbsMax']!) {
    throw ArgumentError('Vertex must be finite and within geometry limits');
  }
  final (node, points) = _editablePath(document, id);
  final shape = node.properties['shape'] as String,
      segments = shape == 'polygon' ? points.length : points.length - 1;
  RangeError.checkValidIndex(
    segmentIndex,
    List.filled(segments, null),
    'segmentIndex',
  );
  if (points.length >= layoutLimits['verticesMax']!) {
    throw StateError('Path vertex limit reached');
  }
  points.insert(segmentIndex + 1, [localX, localY]);
  return _replacePath(
    document,
    node,
    shape == 'line' ? 'polyline' : shape,
    points,
    protectedSeatIds,
  );
}

/// Removes one point while preserving every other point's world position.
VenueLayoutDocument removePathVertex(
  VenueLayoutDocument document,
  String id,
  int index, {
  Set<String> protectedSeatIds = const {},
}) {
  final (node, points) = _editablePath(document, id);
  final shape = node.properties['shape'] as String,
      minimum = shape == 'polygon'
          ? layoutLimits['polygonVerticesMin']!
          : layoutLimits['verticesMin']!;
  RangeError.checkValidIndex(index, points, 'index');
  if (points.length <= minimum) {
    throw StateError('Path must retain at least $minimum vertices');
  }
  points.removeAt(index);
  return _replacePath(document, node, shape, points, protectedSeatIds);
}

(LayoutNode, List<List<double>>) _editablePath(
  VenueLayoutDocument document,
  String id,
) {
  final byId = {for (final node in document.nodes) node.id: node},
      node = byId[id];
  if (node == null ||
      !const [
        'line',
        'arrow',
        'polyline',
        'polygon',
      ].contains(node.properties['shape'])) {
    throw ArgumentError('Object has no editable path');
  }
  // Match the editor's lock contract, including locked descendants and parents.
  final descendants = <String>{id};
  var changed = true;
  while (changed) {
    changed = false;
    for (final candidate in document.nodes) {
      if (descendants.contains(candidate.parentId) &&
          descendants.add(candidate.id)) {
        changed = true;
      }
    }
  }
  for (final descendant in descendants) {
    LayoutNode? current = byId[descendant];
    final visited = <String>{};
    while (current != null && visited.add(current.id)) {
      if (current.locked) throw StateError('Locked path object');
      current = byId[current.parentId];
    }
  }
  final explicit = node.properties['points'] as List?;
  if (explicit == null &&
      node.properties['shape'] != 'line' &&
      node.properties['shape'] != 'arrow') {
    throw ArgumentError('Path points are required');
  }
  final points =
      explicit
          ?.map((p) => (p as List).map((n) => (n as num).toDouble()).toList())
          .toList() ??
      [
        [-node.width / 2, 0.0],
        [node.width / 2, 0.0],
      ];
  if (points.length < 2 ||
      points.length > layoutLimits['verticesMax']! ||
      points.any(
        (p) =>
            p.length != 2 ||
            p.any(
              (n) => !n.isFinite || n.abs() > layoutLimits['geometryAbsMax']!,
            ),
      )) {
    throw ArgumentError('Invalid path vertices');
  }
  return (node, points);
}

VenueLayoutDocument _replacePath(
  VenueLayoutDocument document,
  LayoutNode node,
  String shape,
  List<List<double>> points,
  Set<String> protectedSeatIds,
) {
  final normalized = shapeFromPoints(
        shape,
        points,
        id: node.id,
        properties: {...node.properties}
          ..remove('pathPattern')
          ..remove('zigzagTeeth')
          ..remove('zigzagAmplitude'),
      ),
      angle = quantize(node.rotation) * pi / 180,
      updated = node.copyWith(
        x: node.x + normalized.x * cos(angle) - normalized.y * sin(angle),
        y: node.y + normalized.x * sin(angle) + normalized.y * cos(angle),
        width: normalized.width,
        height: normalized.height,
        properties: normalized.properties,
      ),
      result = document.copyWith(
        nodes: document.nodes
            .map((n) => n.id == node.id ? updated : n)
            .toList(),
      ),
      reconciled = reconcileSurfaceEdit(
        document,
        result,
        node.id,
        protectedSeatIds: protectedSeatIds,
      ),
      issues = validateDocument(reconciled);
  if (issues.isNotEmpty) {
    throw StateError(
      'Invalid path edit: ${issues.map((i) => i.reason).join(', ')}',
    );
  }
  return reconciled;
}
