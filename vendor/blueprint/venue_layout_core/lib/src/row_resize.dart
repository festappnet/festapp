import 'dart:math' as math;

import 'geometry.dart';
import 'model.dart';
import 'placement.dart' show seatPlacementFree, seatRotationManual;
import 'operations.dart' show layoutSubtree, rowLayoutParameters;

/// Actual descendant geometry in the row root's coordinate system.
/// The root's own placeholder box does not participate.
Map<String, double> rowAssemblyBounds(VenueLayoutDocument document, String id) {
  final root = document.nodes.firstWhere((node) => node.id == id);
  if (root.kind != 'group' || ((root.assembly?['kind'])) != 'rows') {
    throw ArgumentError('Not a row assembly');
  }
  final descendants = layoutSubtree(document, {id})..remove(id);
  final matrices = worldMatrices(document);
  final inverseRoot = inverseMatrix(matrices[id]!);
  return boundsOfPoints(
    document.nodes
        .where((node) => descendants.contains(node.id) && node.kind != 'group')
        .expand(
          (node) =>
              worldHull(node, multiplyMatrix(inverseRoot, matrices[node.id]!)),
        )
        .toList(),
  );
}

/// Resizes row spacing and curvature without scaling or recreating chairs.
///
/// The root transform and canonical generator origin stay unchanged. Callers
/// anchor a handle using the actual old/new [rowAssemblyBounds], whose x/y can
/// change as chairs rotate. Impossible dimensions clamp to chair footprints;
/// manual overrides stay fixed and collisions reject the entire operation.
VenueLayoutDocument resizeRowAssembly(
  VenueLayoutDocument document,
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
    throw ArgumentError('Invalid row assembly dimensions');
  }
  final index = {for (final node in document.nodes) node.id: node};
  final root = index[id];
  if (root == null ||
      root.kind != 'group' ||
      ((root.assembly?['kind'])) != 'rows') {
    throw ArgumentError('Not a row assembly');
  }
  final subtree = layoutSubtree(document, {id});
  for (final node in document.nodes.where(
    (node) => subtree.contains(node.id),
  )) {
    LayoutNode? ancestor = node;
    while (ancestor != null) {
      if (ancestor.locked) throw StateError('Locked row object ${ancestor.id}');
      ancestor = index[ancestor.parentId];
    }
  }
  final baselineBounds = rowAssemblyBounds(document, id);
  if ((baselineBounds['width']! - width).abs() < 1 / 1024 &&
      (baselineBounds['height']! - height).abs() < 1 / 1024)
    return document;
  final params = rowLayoutParameters(document, id);
  final spacing = params['spacing']!.toDouble();
  final rowSpacing = params['rowSpacing']!.toDouble();
  final aisle = params['aisle']!.toDouble();
  final arc = params['arc']!.toDouble();
  final columns = params['seatsPerRow']!.toInt();
  final blocks = params['blocks']!.toInt();
  final rows = params['rows']!.toInt();
  final half = (columns - 1) / 2;
  final slots = <String, (int, int, int)>{};
  for (final node in document.nodes.where(
    (n) => n.parentId == id && n.kind == 'seat',
  )) {
    final components = '${node.properties['slot']}'
        .split(':')
        .map(int.tryParse)
        .toList();
    if (components.length == 3 &&
        components.every((v) => v != null && v >= 0)) {
      final row = components[0]!,
          block = components[1]!,
          column = components[2]!;
      if (row < rows && block < blocks && column < columns)
        slots[node.id] = (row, block, column);
    }
  }
  if (slots.isEmpty) return document;
  final spanX =
      ((blocks - 1) * columns + columns - 1) * spacing + (blocks - 1) * aisle;
  final spanY =
      (rows - 1) * rowSpacing +
      arc.abs() * (half * half - (columns.isEven ? .25 : 0));
  var scaleX = 1.0, scaleY = 1.0;
  var actualSpacing = spacing,
      actualRowSpacing = rowSpacing,
      actualAisle = aisle,
      actualArc = arc;

  VenueLayoutDocument candidate() {
    actualSpacing = spacing * scaleX;
    actualRowSpacing = rowSpacing * scaleY;
    actualAisle = aisle * scaleX;
    actualArc = arc * scaleY;
    // Axis-projected physical footprints provide a safe lower spacing bound.
    // Recompute after clamping because tangent angles depend on spacing.
    var clamped = false;
    for (var pass = 0; pass < 32; pass++) {
      actualArc = arc * actualRowSpacing / rowSpacing;
      var minSpacing = 0.0, minRowSpacing = 0.0;
      for (final entry in slots.entries) {
        final node = index[entry.key]!;
        final angle = math.atan(
          2 * actualArc * (entry.value.$3 - half) / actualSpacing,
        );
        final c = math.cos(angle).abs(), s = math.sin(angle).abs();
        minSpacing = math.max(minSpacing, c * node.width + s * node.height);
        minRowSpacing = math.max(
          minRowSpacing,
          s * node.width + c * node.height,
        );
      }
      final nextSpacing = math.max(actualSpacing, minSpacing + 1 / 1024);
      final nextRowSpacing = math.max(
        actualRowSpacing,
        minRowSpacing + 1 / 1024,
      );
      if ((nextSpacing - actualSpacing).abs() < 1e-8 &&
          (nextRowSpacing - actualRowSpacing).abs() < 1e-8) {
        clamped = true;
        break;
      }
      actualSpacing = nextSpacing;
      actualRowSpacing = nextRowSpacing;
    }
    if (!clamped) {
      // A diagonal bounds every projected chair footprint, even when a steep
      // curve makes the angle/spacing iteration converge slowly.
      final diagonal =
          slots.keys
              .map((id) {
                final node = index[id]!;
                return math.sqrt(
                  node.width * node.width + node.height * node.height,
                );
              })
              .reduce(math.max) +
          1 / 1024;
      actualSpacing = math.max(actualSpacing, diagonal);
      actualRowSpacing = math.max(actualRowSpacing, diagonal);
    }
    scaleX = actualSpacing / spacing;
    scaleY = actualRowSpacing / rowSpacing;
    actualAisle = aisle * scaleX;
    // Arc scales with the requested vertical distribution, not seat height.
    actualArc = arc * scaleY;
    return document.copyWith(
      nodes: document.nodes.map((node) {
        final slot = slots[node.id];
        if (slot != null) {
          return node.copyWith(
            x: seatPlacementFree(document, node)
                ? node.x
                : slot.$2 * (columns * actualSpacing + actualAisle) +
                      slot.$3 * actualSpacing,
            y: seatPlacementFree(document, node)
                ? node.y
                : slot.$1 * actualRowSpacing +
                      actualArc * math.pow(slot.$3 - half, 2),
            rotation: seatRotationManual(document, node)
                ? node.rotation
                : math.atan(2 * actualArc * (slot.$3 - half) / actualSpacing) *
                      180 /
                      math.pi,
          );
        }
        if (node.id == id)
          return node.copyWith(
            assembly: {
              'kind': 'rows',
              ...params,
              'spacing': actualSpacing,
              'rowSpacing': actualRowSpacing,
              'aisle': actualAisle,
              'arc': actualArc,
            },
            properties: node.properties,
          );
        return node;
      }).toList(),
    );
  }

  var result = document;
  // Chair outlines depend on tangent angles. This bounded fixed-point solve
  // accounts for those outlines rather than scaling the assembly's box.
  for (var iteration = 0; iteration < 24; iteration++) {
    result = candidate();
    final bounds = rowAssemblyBounds(result, id);
    final errorX = width - bounds['width']!,
        errorY = height - bounds['height']!;
    final nextX = spanX > 1e-9
        ? math.max(.000001, scaleX + errorX / spanX)
        : scaleX;
    final nextY = spanY > 1e-9
        ? math.max(.000001, scaleY + errorY / spanY)
        : scaleY;
    if ((errorX.abs() < .002 || spanX <= 1e-9) &&
        (errorY.abs() < .002 || spanY <= 1e-9))
      break;
    if ((nextX - scaleX).abs() < 1e-9 && (nextY - scaleY).abs() < 1e-9) break;
    scaleX = nextX;
    scaleY = nextY;
  }
  final bounds = rowAssemblyBounds(result, id);
  result = result.copyWith(
    nodes: result.nodes
        .map(
          (node) => node.id == id
              ? node.copyWith(
                  width: math.max(1, bounds['width']!),
                  height: math.max(1, bounds['height']!),
                )
              : node,
        )
        .toList(),
  );
  final local = VenueLayoutDocument(
    schemaVersion: document.schemaVersion,
    nodes: result.nodes
        .where((n) => subtree.contains(n.id))
        .map(
          (n) => n.id == id
              ? n.copyWith(clearParent: true, x: 0, y: 0, rotation: 0)
              : n,
        )
        .toList(),
  );
  if (layoutCollisions(local).isNotEmpty)
    throw StateError('Row dimensions would overlap chairs or manual overrides');
  return result;
}
