import 'placement.dart';
import 'grid_surface.dart' show snapTableSurfaceToGrid;
import 'dart:math';
import 'model.dart';
import 'geometry.dart';
import 'table_seating.dart';
export 'table_seating.dart';
import 'zigzag.dart';
import 'surface_geometry.dart';
export 'surface_geometry.dart';
export 'transport.dart';

int tableCapacity(LayoutNode n) {
  if (n.surface != null)
    n = n.copyWith(properties: surfaceGeometryProperties(n));
  final seating = TableSeating.fromTable(n),
      pitch = seating.pitch,
      inset = seating.edgePadding * 2,
      endAllowance = seating.edgePadding == 0 ? seating.spacing : 0.0;
  if (n.properties['shape'] == 'polygon') {
    return isBarNode(n) ? 0 : polygonSurfaceSlots(n).length;
  }
  if (isBarNode(n)) {
    final side = _barSide(n);
    final length = side == 'top' || side == 'bottom' ? n.width : n.height;
    return max(0, ((length - inset + endAllowance) / pitch).floor());
  }
  final shape = n.properties['shape'];
  if (['round', 'circle', 'ellipse', 'oval'].contains(shape)) {
    final a = n.width / 2, b = n.height / 2;
    return (max(
      0,
      (pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b))) / pitch).floor(),
    ));
  }
  return (2 * max(0, ((n.width - inset + endAllowance) / pitch).floor()) +
          2 * max(0, ((n.height - inset + endAllowance) / pitch).floor()))
      .toInt();
}

List<int> tableEdgeCapacities(LayoutNode table) {
  if (table.kind != 'table' ||
      isBarNode(table) ||
      [
        'polygon',
        'grid',
        'round',
        'circle',
        'ellipse',
        'oval',
      ].contains(table.surface?['type'] ?? table.properties['shape'])) {
    throw ArgumentError('Edge seating requires a rectangular table');
  }
  final seating = TableSeating.fromTable(table),
      inset = seating.edgePadding * 2,
      allowance = seating.edgePadding == 0 ? seating.spacing : 0.0;
  int capacity(double length) =>
      max(0, ((length - inset + allowance) / seating.pitch).floor());
  return [
    capacity(table.width),
    capacity(table.height),
    capacity(table.width),
    capacity(table.height),
  ];
}

VenueLayoutDocument tableLayout({
  required String shape,
  int count = 6,
  double x = 400,
  double y = 300,
  double width = 180,
  double height = 100,
  String? id,
  TableSeating? seating,
  List<int>? edgeCounts,
}) {
  final table = LayoutNode(
    id: id ?? newLayoutId(),
    kind: 'table',
    x: x,
    y: y,
    width: width,
    height: const {'round', 'circle', 'ellipse'}.contains(shape)
        ? width
        : height,
    surface: {
      'type': const {'round', 'circle', 'ellipse'}.contains(shape)
          ? 'circle'
          : 'rect',
    },
    seating: (seating ?? const TableSeating()).record,
    properties: const {},
  );
  if (!const {
    'round',
    'circle',
    'ellipse',
    'rectangle',
    'rect',
    'roundedRect',
  }.contains(shape))
    throw ArgumentError('Unsupported table surface');
  return reflowTable(
    VenueLayoutDocument(schemaVersion: 2, nodes: [table]),
    table.id,
    count,
    edgeCounts: edgeCounts,
  );
}

List<Map<String, dynamic>> _anchors(LayoutNode table, int count) {
  final seating = TableSeating.fromTable(table),
      inset = seating.edgePadding * 2,
      offset = seating.offset;
  final shape = table.properties['shape'], out = <Map<String, dynamic>>[];
  if (shape == 'polygon') {
    final slots = polygonSurfaceSlots(table);
    if (count > slots.length) throw StateError('Table capacity exceeded');
    return [
      for (var i = 0; i < count; i++)
        slots[((i + .5) * slots.length / count).floor()],
    ];
  }
  if (isBarNode(table)) {
    final side = _barSide(table),
        edge = ['top', 'right', 'bottom', 'left'].indexOf(side);
    final horizontal = edge.isEven;
    final length = horizontal ? table.width : table.height;
    for (var i = 0; i < count; i++) {
      final t = (i + .5) / count,
          along = (t - .5) * (length - inset + seating.spacing);
      out.add({
        'x': horizontal
            ? along
            : edge == 1
            ? table.width / 2 + offset
            : -table.width / 2 - offset,
        'y': horizontal
            ? (edge == 0
                  ? -table.height / 2 - offset
                  : table.height / 2 + offset)
            : along,
        'rotation': <double>[180, 270, 0, 90][edge],
        'kind': 'edge',
        'edge': side,
        't': t,
      });
    }
    return out;
  }

  if (['round', 'circle', 'ellipse', 'oval'].contains(shape)) {
    final a = table.width / 2,
        b = table.height / 2,
        points = List.generate(
          1025,
          (i) => [a * cos(i * pi / 512), b * sin(i * pi / 512)],
        ),
        lengths = <double>[0];
    for (var i = 1; i < points.length; i++) {
      lengths.add(
        lengths.last +
            sqrt(
              pow(points[i][0] - points[i - 1][0], 2) +
                  pow(points[i][1] - points[i - 1][1], 2),
            ),
      );
    }
    for (var i = 0; i < count; i++) {
      final distance = lengths.last * i / count;
      var index = 1;
      while (lengths[index] < distance) {
        index++;
      }
      final t =
              (distance - lengths[index - 1]) /
              (lengths[index] - lengths[index - 1]),
          sampledX =
              points[index - 1][0] +
              t * (points[index][0] - points[index - 1][0]),
          sampledY =
              points[index - 1][1] +
              t * (points[index][1] - points[index - 1][1]),
          // Interpolation is for arc length only. Project back onto the true
          // ellipse so an interpolated chord cannot sink a zero-gap chair.
          parameter = atan2(
            sampledY / b,
            sampledX / a,
          ),
          px = a * cos(parameter),
          py = b * sin(parameter),
          angle = atan2(py / (b * b), px / (a * a)),
              // Stay outside the surface after protocol coordinate/angle rounding.
              // Two coordinate quanta are visually negligible, including at gap 0.
              safeOffset =
              offset + 2 / layoutLimits['coordinateQuantum']!;
      out.add({
        'x': px + safeOffset * cos(angle),
        'y': py + safeOffset * sin(angle),
        'rotation': angle * 180 / pi - 90,
        'kind': 'perimeter',
        't': i / count,
      });
    }
    return out;
  }
  final capacity = tableEdgeCapacities(table);
  final saved = table.seating['edgeCounts'] as List?;
  final counts = List<int>.generate(
    4,
    (i) => saved == null ? 0 : min(capacity[i], saved[i] as int),
  );
  var total = counts.fold<int>(0, (sum, n) => sum + n);
  // Saved edge distribution is a preference when the overall count or size changes.
  while (total > count) {
    var edge = 0;
    for (var i = 1; i < 4; i++) {
      if (counts[i] > counts[edge]) edge = i;
    }
    counts[edge]--;
    total--;
  }
  while (total < count) {
    final candidates =
        List.generate(
          4,
          (i) => i,
        ).where((i) => counts[i] < capacity[i]).toList()..sort((a, b) {
          final ratioA = counts[a] / max(1, capacity[a]),
              ratioB = counts[b] / max(1, capacity[b]);
          final c = ratioA.compareTo(ratioB);
          return c != 0 ? c : a.compareTo(b);
        });
    if (candidates.isEmpty) throw StateError('Table capacity exceeded');
    counts[candidates.first]++;
    total++;
  }
  for (var edge = 0; edge < 4; edge++) {
    for (var i = 0; i < counts[edge]; i++) {
      // Capacity is measured in equal seating cells. Center each seat in
      // its cell so filling an edge cannot shrink spacing below capacity.
      final t = (i + .5) / counts[edge], horizontal = edge % 2 == 0;
      out.add({
        'x': horizontal
            ? (t - .5) * (table.width - inset)
            : (edge == 1
                  ? table.width / 2 + offset
                  : -table.width / 2 - offset),
        'y': horizontal
            ? (edge == 0
                  ? -table.height / 2 - offset
                  : table.height / 2 + offset)
            : (t - .5) * (table.height - inset),
        'rotation': <double>[180, 270, 0, 90][edge],
        'kind': 'edge',
        'edge': ['top', 'right', 'bottom', 'left'][edge],
        't': t,
      });
    }
  }
  return out;
}

/// A rejected table shrink leaves the entire immutable input unchanged.
class TableResizeRejected implements Exception {
  final String tableId;
  final int capacity;
  final Set<String> protectedSeatIds;
  final String message;
  TableResizeRejected({
    required this.tableId,
    required this.capacity,
    required Set<String> protectedSeatIds,
    this.message = 'Reserved or blocked seats prevent shrinking this table.',
  }) : protectedSeatIds = Set.unmodifiable(protectedSeatIds);
  @override
  String toString() => message;
}

VenueLayoutDocument reflowTable(
  VenueLayoutDocument d,
  String tableId,
  int count, {
  bool constrainToCanvas = false,
  Set<String> protectedSeatIds = const {},
  List<int>? edgeCounts,
}) {
  d = reflowCanonicalPins(d, tableId);
  final originalTable = d.nodes.firstWhere((n) => n.id == tableId);
  final seating = TableSeating.fromDocument(d, originalTable);
  final table = originalTable.copyWith(
    properties: {...surfaceGeometryProperties(originalTable)},
    seating: {
      ...seating.record,
      if (originalTable.seating['edgeCounts'] != null)
        'edgeCounts': originalTable.seating['edgeCounts'],
      if (edgeCounts != null) 'edgeCounts': List<int>.of(edgeCounts),
    },
  );
  if (edgeCounts != null) {
    final caps = tableEdgeCapacities(table);
    if (edgeCounts.length != 4 ||
        edgeCounts.any((v) => v < 0) ||
        edgeCounts.fold<int>(0, (sum, n) => sum + n) != count ||
        List.generate(4, (i) => i).any((i) => edgeCounts[i] > caps[i])) {
      throw ArgumentError('Invalid table edge counts');
    }
  }
  if (table.kind != 'table') throw ArgumentError('Target must be a table');
  final nodeIndex = {for (final n in d.nodes) n.id: n};
  final visitedAncestors = <String>{};
  LayoutNode? ancestor = table;
  while (ancestor != null) {
    if (!visitedAncestors.add(ancestor.id))
      throw StateError('Invalid table hierarchy');
    if (ancestor.locked) throw StateError('Locked object ${ancestor.id}');
    ancestor = nodeIndex[ancestor.parentId];
  }
  final capacity = tableCapacity(table);
  if (count < 0 || count > capacity)
    throw ArgumentError('Table capacity is $capacity');
  final attachments = {for (final a in d.attachments) a['seatId']: a};
  bool fixed(LayoutNode n) =>
      n.locked ||
      ((attachments[n.id] != null &&
          attachments[n.id]?['placement']?['mode'] != 'automatic'));
  final seats =
      d.nodes.where((n) => n.kind == 'seat' && n.parentId == tableId).toList()
        ..sort((a, b) {
          final order = (a.properties['slot'] as num? ?? 0).compareTo(
            b.properties['slot'] as num? ?? 0,
          );
          return order != 0 ? order : a.id.compareTo(b.id);
        });
  final seatIds = seats.map((n) => n.id).toSet();
  final protected = {
    for (final seat in seats)
      if (seat.locked || protectedSeatIds.contains(seat.id)) seat.id,
  };
  final unitsBySeat = <String, Set<String>>{};
  for (final unit in d.selectionUnits) {
    final members = (unit['nodeIds'] as List).cast<String>().toSet();
    if (!members.any(seatIds.contains)) continue;
    for (final id in members.where(seatIds.contains)) {
      unitsBySeat[id] = members;
    }
    if (members.any(protectedSeatIds.contains) ||
        members.any((id) => !seatIds.contains(id)))
      protected.addAll(members.where(seatIds.contains));
  }
  if (protected.length > count)
    throw TableResizeRejected(
      tableId: tableId,
      capacity: count,
      protectedSeatIds: protected,
    );
  final retainedIds = {...seatIds};
  final seatRank = {for (var i = 0; i < seats.length; i++) seats[i].id: i};
  final removalOrder = seats.toList()
    ..sort((a, b) {
      final manualA = fixed(a) ? 1 : 0, manualB = fixed(b) ? 1 : 0;
      final priority = manualA.compareTo(manualB);
      return priority != 0
          ? priority
          : seatRank[b.id]!.compareTo(seatRank[a.id]!);
    });
  for (final seat in removalOrder) {
    if (retainedIds.length <= count) break;
    if (!retainedIds.contains(seat.id)) continue;
    final batch = unitsBySeat[seat.id] ?? {seat.id};
    if (batch.any(protected.contains) ||
        batch.any((id) => !seatIds.contains(id)))
      continue;
    retainedIds.removeAll(batch);
  }
  if (retainedIds.length > count)
    throw TableResizeRejected(
      tableId: tableId,
      capacity: count,
      protectedSeatIds: protected,
    );
  final retained = seats.where((n) => retainedIds.contains(n.id)).toList();
  // A free indivisible unit may remove more than one surplus seat. Do not
  // invent replacement identities during a shrink just to fill an odd gap.
  if (seats.length > count && retained.length < count) count = retained.length;
  final deletedIds = seatIds.difference(retainedIds);
  final next = List.generate(
    count,
    (i) => i < retained.length
        ? retained[i]
        : LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            width: seating.width,
            height: seating.height,
            parentId: tableId,
            label: '${i + 1}',
            properties: {
              'symbol': 'chair',

              if (isBarNode(table)) 'furniture': 'stool',
            },
          ),
  );
  final matrix = constrainToCanvas ? worldMatrices(d)[tableId]! : null;
  if (matrix != null &&
      worldHull(table, matrix).any(
        (p) =>
            p[0] < (d.canvas['x'] as num) - 1e-7 ||
            p[1] < (d.canvas['y'] as num) - 1e-7 ||
            p[0] > (d.canvas['x'] as num) + (d.canvas['width'] as num) + 1e-7 ||
            p[1] > (d.canvas['y'] as num) + (d.canvas['height'] as num) + 1e-7,
      )) {
    throw StateError('Target table is outside the canvas');
  }
  final tableMatrix = worldMatrices(d)[tableId]!,
      inverse = inverseMatrix(tableMatrix);
  final own = layoutSubtree(d, {tableId});
  final extent =
      max(seating.width, seating.height) + seating.gap + seating.spacing;
  final body = nodeBounds(d, originalTable);
  final neighbors = d.nodes.any((n) => !own.contains(n.id) && _chairObstacle(n))
      ? spatialIndexFor(d).query({
          'x': body['x']! - extent,
          'y': body['y']! - extent,
          'width': body['width']! + extent * 2,
          'height': body['height']! + extent * 2,
        })
      : <String>{};
  final externalHulls = [
    for (final id in neighbors)
      if (!own.contains(id) && _chairObstacle(nodeIndex[id]!))
        worldHull(
          nodeIndex[id]!,
          multiplyMatrix(inverse, worldMatrices(d)[id]!),
        ),
  ];
  bool inside(LayoutNode n) {
    if (externalHulls.any(
      (other) => polygonsOverlap(other, worldHull(n, localMatrix(n))),
    ))
      return false;
    if (matrix == null) return true;
    return worldHull(n, multiplyMatrix(matrix, localMatrix(n))).every(
      (p) =>
          p[0] >= (d.canvas['x'] as num) - 1e-7 &&
          p[1] >= (d.canvas['y'] as num) - 1e-7 &&
          p[0] <= (d.canvas['x'] as num) + (d.canvas['width'] as num) + 1e-7 &&
          p[1] <= (d.canvas['y'] as num) + (d.canvas['height'] as num) + 1e-7,
    );
  }

  final fixedHulls = <List<List<double>>>[], tableHull = localHull(table);
  for (final seat in next.where(fixed)) {
    final hull = worldHull(seat, localMatrix(seat));
    if (!inside(seat) ||
        polygonsOverlap(hull, tableHull) ||
        fixedHulls.any((other) => polygonsOverlap(hull, other))) {
      throw StateError('Fixed chairs prevent a collision-free table layout');
    }
    fixedHulls.add(hull);
  }
  final preferred = _anchors(table, count);
  final selectedAnchors = <String, Map<String, dynamic>>{};
  bool pack(List<Map<String, dynamic>> anchors) {
    final occupied = [...fixedHulls];
    selectedAnchors.clear();
    for (var i = 0; i < next.length; i++) {
      final seat = next[i];
      if (fixed(seat)) continue;
      final target = preferred[i];
      final tx = (target['x'] as num).toDouble(),
          ty = (target['y'] as num).toDouble();
      double deviation(Map<String, dynamic> anchor) {
        final dx = (anchor['x'] as num) - tx, dy = (anchor['y'] as num) - ty;
        return dx * dx + dy * dy;
      }

      Iterable<Map<String, dynamic>> ordered() sync* {
        if (identical(anchors, preferred) || anchors.contains(target))
          yield target;
        // Rank fallback slots lazily: the regular, unconstrained path never
        // allocates or sorts a second list for each chair.
        final alternatives =
            anchors.where((anchor) => !identical(anchor, target)).toList()
              ..sort((a, b) => deviation(a).compareTo(deviation(b)));
        yield* alternatives;
      }

      var placed = false;
      for (final a in ordered()) {
        final candidate = seat.copyWith(
              x: (a['x'] as num).toDouble(),
              y: (a['y'] as num).toDouble(),
              rotation: seatRotationManual(d, seat)
                  ? seat.rotation
                  : (a['rotation'] as num).toDouble(),
            ),
            hull = worldHull(candidate, localMatrix(candidate));
        if (!inside(candidate) ||
            polygonsOverlap(hull, tableHull) ||
            occupied.any((other) => polygonsOverlap(hull, other)))
          continue;
        occupied.add(hull);
        selectedAnchors[seat.id] = a;
        placed = true;
        break;
      }
      if (!placed) return false;
    }
    return true;
  }

  if (!pack(preferred)) {
    // Ordinary tables use their complete capacity grid. Bound fallback sampling
    // for exceptionally large tables instead of allocating millions of anchors.
    final fallbackCount = min(capacity, max(count + 8, count * 2));
    final full = _anchors(table, fallbackCount);
    if (!pack(full) && !pack([...preferred, ...full])) {
      throw StateError('No collision-free chair position is available');
    }
  }
  final placed = <LayoutNode>[
    for (var i = 0; i < next.length; i++)
      if (fixed(next[i]))
        next[i]
      else
        next[i].copyWith(
          x: (selectedAnchors[next[i].id]!['x'] as num).toDouble(),
          y: (selectedAnchors[next[i].id]!['y'] as num).toDouble(),
          rotation: seatRotationManual(d, next[i])
              ? next[i].rotation
              : (selectedAnchors[next[i].id]!['rotation'] as num).toDouble(),
          properties: {...next[i].properties, 'slot': i},
        ),
  ];
  final actualEdges = List<int>.filled(4, 0);
  if (table.seating.containsKey('edgeCounts')) {
    for (final seat in placed) {
      final edge = fixed(seat)
          ? (seat.x.abs() / table.width > seat.y.abs() / table.height
                ? (seat.x < 0 ? 'left' : 'right')
                : (seat.y < 0 ? 'top' : 'bottom'))
          : selectedAnchors[seat.id]?['edge'];
      final index = [
        'top',
        'right',
        'bottom',
        'left',
      ].indexOf(edge as String? ?? '');
      if (index >= 0) actualEdges[index]++;
    }
    if (edgeCounts != null &&
        !List.generate(
          4,
          (i) => i,
        ).every((i) => actualEdges[i] == edgeCounts[i])) {
      throw StateError(
        'Fixed chairs or obstacles prevent the requested edge distribution',
      );
    }
  }
  final removed = seats.map((n) => n.id).toSet();
  return d.copyWith(
    nodes: [
      ...d.nodes
          .where((n) => !removed.contains(n.id))
          .map(
            (n) => n.id == tableId
                ? (originalTable.copyWith(
                    seating: {
                      ...seating.record,
                      if (table.seating.containsKey('edgeCounts'))
                        'edgeCounts': actualEdges,
                    },
                  ))
                : n,
          ),
      ...placed,
    ],
    selectionUnits: d.selectionUnits
        .where((u) => !(u['nodeIds'] as List).any(deletedIds.contains))
        .toList(),
    attachments: [
      ...d.attachments.where(
        (a) => a['targetId'] != tableId && !deletedIds.contains(a['seatId']),
      ),
      for (final seat in placed)
        if (fixed(seat) && attachments[seat.id] != null)
          attachments[seat.id]!
        else
          {
            if (attachments[seat.id]?['id'] != null)
              'id': attachments[seat.id]!['id'],
            'seatId': seat.id,
            'targetId': tableId,
            'rotationMode': attachments[seat.id]?['rotationMode'] ?? 'auto',
            'placement': {'mode': 'automatic'},
          },
    ],
  );
}

bool _chairObstacle(LayoutNode n) =>
    n.kind == 'seat' ||
    n.kind == 'table' ||
    n.kind == 'furniture' ||
    n.properties['obstacle'] == true ||
    n.properties['role'] == 'obstacle';

bool _tableBodiesClear(
  VenueLayoutDocument d,
  Set<String> tableIds,
  LayoutSpatialIndex index,
  Map<String, LayoutNode> byId,
) {
  for (final table in d.nodes.where((n) => tableIds.contains(n.id))) {
    final own = layoutSubtree(d, {table.id});
    final hull = worldHull(table, index.matrices[table.id]!);
    for (final id in index.query(boundsOfPoints(hull))) {
      if (own.contains(id) || !_chairObstacle(byId[id]!)) continue;
      if (polygonsOverlap(hull, worldHull(byId[id]!, index.matrices[id]!))) {
        return false;
      }
    }
  }
  return true;
}

bool _tableChairsClear(VenueLayoutDocument d, Set<String> tableIds) {
  if (tableIds.isEmpty) return true;
  final index = LayoutSpatialIndex(d),
      byId = {for (final n in d.nodes) n.id: n};
  if (!_tableBodiesClear(d, tableIds, index, byId)) return false;
  for (final seat in d.nodes.where(
    (n) => n.kind == 'seat' && tableIds.contains(n.parentId),
  )) {
    final hull = worldHull(seat, index.matrices[seat.id]!);
    for (final id in index.query(boundsOfPoints(hull))) {
      if (id == seat.id || id == seat.parentId || !_chairObstacle(byId[id]!))
        continue;
      if (polygonsOverlap(hull, worldHull(byId[id]!, index.matrices[id]!)))
        return false;
    }
  }
  return true;
}

/// Repositions attached chairs onto free perimeter slots at walls or neighbours.
/// Call with the transformed gesture baseline. Nearby physical objects obstruct
/// seats; canvas size, seat identities, slot numbers and locked positions stay
/// unchanged. Manual positions yield when obstructed. If no complete packing
/// exists, the bounded-movement caller rejects the proposed translation.
VenueLayoutDocument reflowTablesAtCanvasEdges(
  VenueLayoutDocument d,
  Set<String> tableIds,
) {
  if (tableIds.isEmpty) return d;
  {
    for (final id in tableIds)
      d = reflowTable(
        d,
        id,
        d.nodes.where((n) => n.parentId == id && n.kind == 'seat').length,
        constrainToCanvas: true,
      );
    return d;
  }
}

VenueLayoutDocument snapAttachedChairPosition(
  VenueLayoutDocument d,
  String seatId, {
  double tolerance = 32,
}) {
  if (!tolerance.isFinite || tolerance < 0)
    throw ArgumentError('Invalid chair snap tolerance');
  final seat = d.nodes.firstWhere((n) => n.id == seatId),
      byId = {for (final n in d.nodes) n.id: n},
      table = byId[seat.parentId],
      attachment = d.attachments
          .where((a) => a['seatId'] == seatId)
          .firstOrNull;
  if (seat.kind != 'seat' ||
      table?.kind != 'table' ||
      attachment?['targetId'] != table!.id)
    return d;
  _unlocked(d, {seatId});
  final others = d.nodes
          .where(
            (n) => n.kind == 'seat' && n.parentId == table.id && n.id != seatId,
          )
          .toList(),
      slots = [
        ..._anchors(table, min(tableCapacity(table), others.length + 1)),
        ..._anchors(
          table,
          min(tableCapacity(table), max(16, (others.length + 1) * 2)),
        ),
      ],
      matrix = worldMatrices(d)[table.id]!;
  slots.sort((a, b) {
    double distance(Map<String, dynamic> a) =>
        pow((a['x'] as num) - seat.x, 2).toDouble() +
        pow((a['y'] as num) - seat.y, 2).toDouble();
    return distance(a).compareTo(distance(b));
  });
  for (final slot in slots) {
    if (pow((slot['x'] as num) - seat.x, 2) +
            pow((slot['y'] as num) - seat.y, 2) >
        tolerance * tolerance)
      continue;
    final next = seat.copyWith(
          x: (slot['x'] as num).toDouble(),
          y: (slot['y'] as num).toDouble(),
          rotation: (slot['rotation'] as num).toDouble(),
        ),
        hull = worldHull(next, localMatrix(next));
    if (polygonsOverlap(hull, localHull(table)) ||
        others.any((n) => polygonsOverlap(hull, worldHull(n, localMatrix(n)))))
      continue;
    final world = multiplyMatrix(matrix, localMatrix(next));
    bool inside(List<double> m) => worldHull(next, m).every(
      (p) =>
          p[0] >= (d.canvas['x'] as num) - 1e-7 &&
          p[1] >= (d.canvas['y'] as num) - 1e-7 &&
          p[0] <= (d.canvas['x'] as num) + (d.canvas['width'] as num) + 1e-7 &&
          p[1] <= (d.canvas['y'] as num) + (d.canvas['height'] as num) + 1e-7,
    );
    if (!inside(world) || !inside(world.map(quantize).toList())) continue;
    return d.copyWith(
      nodes: d.nodes.map((n) => n.id == seatId ? next : n).toList(),
      attachments: d.attachments
          .map(
            (a) => a['seatId'] == seatId
                ? {
                    ...a,
                    'placement': {'mode': 'free'},
                  }
                : a,
          )
          .toList(),
    );
  }
  return d;
}

VenueLayoutDocument cloneLayout(
  VenueLayoutDocument d, {
  double dx = 0,
  double dy = 0,
}) {
  final issues = validateDocument(d);
  if (issues.isNotEmpty) throw InvalidLayoutDocument(issues, d.toJson());
  final ids = <String, String>{for (final n in d.nodes) n.id: newLayoutId()};
  for (final records in [
    d.sections,
    d.selectionUnits,
    d.presets,
    d.attachments,
  ]) {
    for (final r in records) {
      if (r['id'] is String) ids[r['id']] = newLayoutId();
    }
  }
  const references = {
    'id',
    'parentId',
    'rootId',
    'seatId',
    'targetId',
    'assemblyId',
    'nodeId',
    'groupId',
    'sectionId',
    'selectionUnitId',
  };
  dynamic remap(dynamic value, [String? key]) {
    if (value is String)
      return references.contains(key) ? ids[value] ?? value : value;
    if (value is List)
      return value
          .map((v) => key == 'nodeIds' && v is String ? ids[v] ?? v : remap(v))
          .toList();
    if (value is Map)
      return <String, dynamic>{
        for (final e in value.entries)
          e.key as String: remap(e.value, e.key as String),
      };
    return value;
  }

  final json = d.toJson();
  json['presets'] = <Map<String, dynamic>>[];
  final result =
      VenueLayoutDocument.fromJson(
        Map<String, dynamic>.from(remap(json)),
      ).copyWith(
        presets: [
          for (final p in d.presets)
            {
              ...p,
              'id': ids[p['id']],
              'document': cloneLayout(
                VenueLayoutDocument.fromJson(
                  Map<String, dynamic>.from(p['document']),
                ),
              ).toJson(),
            },
        ],
      );
  return result.copyWith(
    nodes: result.nodes
        .map(
          (n) => n.parentId == null ? n.copyWith(x: n.x + dx, y: n.y + dy) : n,
        )
        .toList(),
  );
}

Set<String> layoutSubtree(VenueLayoutDocument d, Set<String> ids) {
  final result = {...ids};
  var changed = true;
  while (changed) {
    changed = false;
    for (final n in d.nodes) {
      if (result.contains(n.parentId) && result.add(n.id)) changed = true;
    }
  }
  return result;
}

void _unlocked(VenueLayoutDocument d, Set<String> ids) {
  final subtree = layoutSubtree(d, ids),
      byId = {for (final n in d.nodes) n.id: n};
  for (final id in subtree) {
    var n = byId[id];
    while (n != null) {
      if (n.locked)
        throw StateError('Locked object ${n.label.isEmpty ? n.id : n.label}');
      n = byId[n.parentId];
    }
  }
}

VenueLayoutDocument transformNodes(
  VenueLayoutDocument d,
  Set<String> ids, {
  double dx = 0,
  double dy = 0,
  double rotation = 0,
  bool cornerPivot = false,
}) {
  _unlocked(d, ids);
  final byId = {for (final node in d.nodes) node.id: node};
  final subtree = layoutSubtree(d, ids),
      roots = d.nodes
          .where((n) => ids.contains(n.id) && !subtree.contains(n.parentId))
          .toList(),
      matrices = worldMatrices(d),
      points = roots.expand((n) => worldHull(n, matrices[n.id]!)).toList(),
      bounds = roots.any((n) => n.kind == 'group' && (n.assembly == null))
          ? selectionBounds(d, ids)
          : boundsOfPoints(points),
      cx = bounds['x']! + (cornerPivot ? 0 : bounds['width']! / 2),
      cy = bounds['y']! + (cornerPivot ? 0 : bounds['height']! / 2),
      r = rotation * pi / 180,
      c = cos(r),
      s = sin(r),
      rootIds = roots.map((n) => n.id).toSet();
  final movedNodes = d.nodes.map((n) {
    if (!rootIds.contains(n.id)) return n;
    final m = matrices[n.id]!,
        x = m[4] - cx,
        y = m[5] - cy,
        world = [cx + c * x - s * y + dx, cy + s * x + c * y + dy],
        parent = matrices[n.parentId],
        local = parent == null
            ? world
            : transformPoint(inverseMatrix(parent), world[0], world[1]);
    return n.copyWith(
      x: quantize(local[0]),
      y: quantize(local[1]),
      rotation: quantize(n.rotation + rotation),
    );
  }).toList();
  final movedById = {for (final n in movedNodes) n.id: n};
  return d.copyWith(
    nodes: movedNodes,
    attachments: [
      for (final a in d.attachments)
        if (rootIds.contains(a['seatId']))
          {
            ...a,
            if (movedById[a['seatId']]!.x != byId[a['seatId']]!.x ||
                movedById[a['seatId']]!.y != byId[a['seatId']]!.y)
              'placement': {'mode': 'free'},
            if (rotation != 0) 'rotationMode': 'manual',
          }
        else
          a,
    ],
  );
}

/// Translates an assembly inside the fixed canvas. Derive every preview from
/// the gesture baseline.
/// Physical furniture and chairs constrain placement; decorative labels do not.
/// Move the complete assembly rigidly. Seating repair belongs to explicit
/// layout operations, never to pointer translation.
VenueLayoutDocument translateLayoutWithinCanvas(
  VenueLayoutDocument d,
  Set<String> ids, {
  double dx = 0,
  double dy = 0,
}) => _moveLayoutWithinCanvas(d, ids, dx: dx, dy: dy);

VenueLayoutDocument moveLayoutWithinCanvas(
  VenueLayoutDocument d,
  Set<String> ids, {
  double dx = 0,
  double dy = 0,
}) => _moveLayoutWithinCanvas(d, ids, dx: dx, dy: dy);

VenueLayoutDocument _moveLayoutWithinCanvas(
  VenueLayoutDocument d,
  Set<String> ids, {
  double dx = 0,
  double dy = 0,
}) {
  if (!dx.isFinite || !dy.isFinite) {
    throw ArgumentError('Translation must be finite');
  }
  final subtree = layoutSubtree(d, ids),
      moving = d.nodes
          .where((n) => subtree.contains(n.id) && n.kind != 'group')
          .toList();
  if (moving.isEmpty) return d;
  _unlocked(d, ids);
  final tables = moving
          .where((n) => n.kind == 'table')
          .map((n) => n.id)
          .toSet(),
      left = (d.canvas['x'] as num).toDouble(),
      top = (d.canvas['y'] as num).toDouble(),
      right = left + (d.canvas['width'] as num),
      bottom = top + (d.canvas['height'] as num);
  Map<String, double> bounds(VenueLayoutDocument doc, List<LayoutNode> nodes) {
    final matrices = worldMatrices(doc);
    return boundsOfPoints(
      nodes.expand((n) {
        final matrix = matrices[n.id]!;
        // Both the unrounded scene transform and public quantized nodeBounds
        // must fit. A rotated parent's matrix can differ by one protocol quantum.
        return [
          ...worldHull(n, matrix),
          ...worldHull(n, matrix.map(quantize).toList()),
        ];
      }).toList(),
    );
  }

  List<double>? clamp(Map<String, double> b, double x, double y) {
    final minX = left - b['x']!,
        maxX = right - b['x']! - b['width']!,
        minY = top - b['y']!,
        maxY = bottom - b['y']! - b['height']!;
    if (minX > maxX + 1e-7 || minY > maxY + 1e-7) return null;
    return [x.clamp(minX, max(minX, maxX)), y.clamp(minY, max(minY, maxY))];
  }

  bool contained(Map<String, double> b) =>
      b['x']! >= left - 1e-7 &&
      b['y']! >= top - 1e-7 &&
      b['x']! + b['width']! <= right + 1e-7 &&
      b['y']! + b['height']! <= bottom + 1e-7;
  final rigid = clamp(bounds(d, moving), dx, dy);
  if (rigid == null) return d;
  var x = rigid[0], y = rigid[1];
  for (var attempt = 0; attempt < 4; attempt++) {
    final candidate = transformNodes(d, ids, dx: x, dy: y),
        b = bounds(
          candidate,
          candidate.nodes
              .where((n) => subtree.contains(n.id) && n.kind != 'group')
              .toList(),
        );
    if (contained(b))
      return _tableChairsClear(candidate, tables) ? candidate : d;
    final correction = clamp(b, 0, 0);
    if (correction == null) break;
    final quantum = 1 / layoutLimits['coordinateQuantum']!;
    x += correction[0] + correction[0].sign * quantum;
    y += correction[1] + correction[1].sign * quantum;
  }
  return d;
}

VenueLayoutDocument resizeNode(
  VenueLayoutDocument d,
  String id,
  double width,
  double height, {
  Set<String> protectedSeatIds = const {},
}) {
  _unlocked(d, {id});
  if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0)
    throw ArgumentError('Dimensions must be finite and positive');
  final resizeTarget = d.nodes.firstWhere((n) => n.id == id);
  if (resizeTarget.kind == 'table') {
    final surface = Map<String, dynamic>.from(resizeTarget.surface!);
    if (surface['type'] == 'circle' && (width - height).abs() > 1 / 1024)
      throw StateError('circle_requires_equal_dimensions');
    if (surface['type'] == 'grid') {
      if ((width / resizeTarget.width - height / resizeTarget.height).abs() >
          1 / 1024)
        throw StateError('grid_resize_requires_uniform_module');
      surface['moduleSize'] =
          (surface['moduleSize'] as num) * width / resizeTarget.width;
    }
    final resized = resizeTarget.copyWith(
      width: width,
      height: height,
      surface: surface,
    );
    final next = d.copyWith(
      nodes: [for (final n in d.nodes) n.id == id ? resized : n],
    );
    return reflowTable(
      next,
      id,
      min(
        d.nodes.where((n) => n.parentId == id && n.kind == 'seat').length,
        tableCapacity(resized),
      ),
      protectedSeatIds: protectedSeatIds,
    );
  }
  if (isZigzagNode(resizeTarget)) {
    return resizeZigzagLine(d, id, width, height);
  }
  final original = d.nodes.firstWhere((n) => n.id == id),
      points = original.properties['points'],
      resized = original.copyWith(
        width: width,
        height: height,
        properties:
            points is List &&
                const [
                  'polygon',
                  'polyline',
                  'line',
                  'arrow',
                ].contains(original.properties['shape'])
            ? {
                ...original.properties,
                if (original.properties['holes'] is List)
                  'holes': [
                    for (final hole in original.properties['holes'] as List)
                      [
                        for (final p in hole as List)
                          [
                            quantize((p[0] as num) * width / original.width),
                            quantize((p[1] as num) * height / original.height),
                          ],
                      ],
                  ],
                'points': points
                    .map(
                      (p) => [
                        quantize((p[0] as num) * width / original.width),
                        quantize((p[1] as num) * height / original.height),
                      ],
                    )
                    .toList(),
              }
            : original.properties,
      ),
      result = d.copyWith(
        nodes: d.nodes.map((n) => n.id == id ? resized : n).toList(),
      );
  return original.kind == 'table'
      ? reflowTable(
          result,
          id,
          min(
            d.nodes.where((n) => n.parentId == id && n.kind == 'seat').length,
            tableCapacity(resized),
          ),
          protectedSeatIds: protectedSeatIds,
        )
      : result;
}

/// Edits a vertex in the node's original local coordinate system. The path is
/// recentered without moving any other vertex in world space.
VenueLayoutDocument updatePathVertex(
  VenueLayoutDocument d,
  String id,
  int index,
  double localX,
  double localY, {
  Set<String> protectedSeatIds = const {},
}) {
  _unlocked(d, {id});
  if (!localX.isFinite ||
      !localY.isFinite ||
      localX.abs() > layoutLimits['geometryAbsMax']! ||
      localY.abs() > layoutLimits['geometryAbsMax']!) {
    throw ArgumentError(
      'Vertex coordinates must be finite and within geometry limits',
    );
  }
  final node = d.nodes.firstWhere((n) => n.id == id),
      shape = node.properties['shape'];
  if (!const ['polygon', 'polyline', 'line', 'arrow'].contains(shape)) {
    throw ArgumentError('Object has no editable path');
  }
  final explicit = node.properties['points'] as List?;
  if (explicit == null && shape != 'line' && shape != 'arrow') {
    throw ArgumentError('Path points are required');
  }
  final points =
      explicit
          ?.map((p) => (p as List).map((v) => (v as num).toDouble()).toList())
          .toList() ??
      [
        [-node.width / 2, 0.0],
        [node.width / 2, 0.0],
      ];
  RangeError.checkValidIndex(index, points, 'index');
  points[index] = [localX, localY];
  final normalized = shapeFromPoints(
        shape as String,
        points,
        id: node.id,
        properties: {...node.properties}
          ..remove('pathPattern')
          ..remove('zigzagTeeth')
          ..remove('zigzagAmplitude'),
      ),
      angle = quantize(node.rotation) * pi / 180,
      centerX = normalized.x * cos(angle) - normalized.y * sin(angle),
      centerY = normalized.x * sin(angle) + normalized.y * cos(angle),
      updated = node.copyWith(
        x: node.x + centerX,
        y: node.y + centerY,
        width: normalized.width,
        height: normalized.height,
        properties: normalized.properties,
      );
  final result = d.copyWith(
    nodes: d.nodes.map((n) => n.id == id ? updated : n).toList(),
  );
  return reconcileSurfaceEdit(
    d,
    result,
    id,
    protectedSeatIds: protectedSeatIds,
  );
}

/// Changes placement intent in one physical command. The node transform remains
/// the sole rendered pose; manual rotation is independent of placement.
VenueLayoutDocument setTableSeatPlacement(
  VenueLayoutDocument document,
  String seatId,
  Map<String, dynamic> placement, {
  Set<String> protectedSeatIds = const {},
}) {
  {}
  final seat = document.nodes.firstWhere((node) => node.id == seatId);
  final table = document.nodes.firstWhere((node) => node.id == seat.parentId);
  if (seat.kind != 'seat' || table.kind != 'table')
    throw ArgumentError('Select a chair attached to a table');
  _unlocked(document, {seatId, table.id});
  final existing = seatAttachment(document, seatId);
  if (sameLayoutValue(existing?['placement'], placement)) return document;
  final next = document.copyWith(
    attachments: [
      for (final attachment in document.attachments)
        if (attachment['seatId'] != seatId) attachment,
      {
        if (existing?['id'] != null) 'id': existing!['id'],
        'seatId': seatId,
        'targetId': table.id,
        'rotationMode': existing?['rotationMode'] ?? 'auto',
        'placement': placement,
      },
    ],
  );
  final issues = validateDocument(next);
  if (issues.isNotEmpty) throw InvalidLayoutDocument(issues, next.toJson());
  if (placement['mode'] == 'free') return next;
  return reflowTable(
    next,
    table.id,
    next.nodes
        .where((node) => node.parentId == table.id && node.kind == 'seat')
        .length,
    protectedSeatIds: protectedSeatIds,
  );
}

VenueLayoutDocument detachSeat(VenueLayoutDocument d, String id) {
  _unlocked(d, {id});
  final m = worldMatrix(d, d.nodes.firstWhere((n) => n.id == id));
  return d.copyWith(
    nodes: d.nodes
        .map(
          (n) => n.id == id
              ? n.copyWith(
                  clearParent: true,
                  x: m[4],
                  y: m[5],
                  rotation: atan2(m[1], m[0]) * 180 / pi,
                  properties: n.properties,
                )
              : n,
        )
        .toList(),
    attachments: d.attachments.where((a) => a['seatId'] != id).toList(),
  );
}

VenueLayoutDocument attachSeat(
  VenueLayoutDocument d,
  String seatId,
  String tableId,
) {
  final seat = d.nodes.firstWhere((n) => n.id == seatId),
      table = d.nodes.firstWhere((n) => n.id == tableId),
      byId = {for (final n in d.nodes) n.id: n};
  if (seat.kind != 'seat' || table.kind != 'table') {
    throw ArgumentError('Attach requires a chair and a table');
  }
  _unlocked(d, {seatId});
  LayoutNode? ancestor = table;
  while (ancestor != null) {
    if (ancestor.locked) throw StateError('Locked target table');
    ancestor = byId[ancestor.parentId];
  }
  if (seat.parentId == tableId &&
      d.attachments.any(
        (a) => a['seatId'] == seatId && a['targetId'] == tableId,
      ))
    return d;
  {
    if (d.selectionUnits.any(
      (u) =>
          (u['nodeIds'] as List).length > 1 &&
          (u['nodeIds'] as List).contains(seatId),
    ))
      throw StateError('atomic_unit_requires_full_move');
    final profile = TableSeating.fromDocument(d, table),
        old = seatAttachment(d, seatId);
    final result = d.copyWith(
      nodes: [
        for (final n in d.nodes)
          n.id == seatId
              ? n.copyWith(
                  parentId: tableId,
                  width: profile.width,
                  height: profile.height,
                  properties: {...n.properties, 'slot': 100000},
                )
              : n,
      ],
      attachments: [
        ...d.attachments.where((a) => a['seatId'] != seatId),
        {
          if (old?['id'] != null) 'id': old!['id'],
          'seatId': seatId,
          'targetId': tableId,
          'rotationMode': old?['rotationMode'] ?? 'auto',
          'placement': {'mode': 'automatic'},
        },
      ],
    );
    return reflowTable(
      result,
      tableId,
      result.nodes
          .where((n) => n.parentId == tableId && n.kind == 'seat')
          .length,
      constrainToCanvas: true,
    );
  }
}

/// Uses the exact atomic attachment operation for hover and drop availability.
bool canAttachSeatToTable(
  VenueLayoutDocument d,
  String seatId,
  String tableId,
) {
  try {
    attachSeat(d, seatId, tableId);
    return true;
  } on ArgumentError {
    return false;
  } on StateError {
    return false;
  }
}

VenueLayoutDocument groupNodes(VenueLayoutDocument d, Set<String> ids) {
  _unlocked(d, ids);
  final roots = d.nodes.where((n) => ids.contains(n.id)).toList();
  if (roots.any((n) => n.parentId != roots.first.parentId))
    throw ArgumentError('Group siblings only');
  final matrices = worldMatrices(d),
      b = boundsOfPoints(
        roots.expand((n) => worldHull(n, matrices[n.id]!)).toList(),
      ),
      cx = b['x']! + b['width']! / 2,
      cy = b['y']! + b['height']! / 2,
      id = newLayoutId(),
      group = LayoutNode(
        id: id,
        kind: 'group',
        x: cx,
        y: cy,
        width: max(1, b['width']!),
        height: max(1, b['height']!),
      );
  return d.copyWith(
    nodes: [
      ...d.nodes.map((n) {
        if (!ids.contains(n.id)) return n;
        final m = matrices[n.id]!;
        return n.copyWith(
          parentId: id,
          x: m[4] - cx,
          y: m[5] - cy,
          rotation: atan2(m[1], m[0]) * 180 / pi,
        );
      }),
      group,
    ],
  );
}

VenueLayoutDocument ungroupNodes(VenueLayoutDocument d, Set<String> ids) {
  _unlocked(d, ids);
  final matrices = worldMatrices(d);
  final removedGroups = d.nodes
      .where((n) => ids.contains(n.id) && n.kind == 'group')
      .map((n) => n.id)
      .toSet();
  return d.copyWith(
    nodes: d.nodes.where((n) => !ids.contains(n.id) || n.kind != 'group').map((
      n,
    ) {
      if (!ids.contains(n.parentId)) return n;
      final m = matrices[n.id]!;
      return n.copyWith(
        clearParent: true,
        x: m[4],
        y: m[5],
        rotation: atan2(m[1], m[0]) * 180 / pi,
      );
    }).toList(),
    sections: d.sections
        .where((s) => !removedGroups.contains(s['rootId']))
        .toList(),
    attachments: d.attachments
        .where((a) => !removedGroups.contains(a['targetId']))
        .toList(),
  );
}

VenueLayoutDocument fitCanvas(VenueLayoutDocument d, {double padding = 40}) {
  final b = documentBounds(d);
  return d.copyWith(
    canvas: {
      ...d.canvas,
      'x': b['x']! - padding,
      'y': b['y']! - padding,
      'width': max(64, b['width']! + padding * 2),
      'height': max(64, b['height']! + padding * 2),
    },
  );
}

VenueLayoutDocument resizeCanvas(
  VenueLayoutDocument d,
  double width,
  double height, {
  bool center = false,
}) {
  final x =
          (d.canvas['x'] as num).toDouble() +
          (center ? ((d.canvas['width'] as num) - width) / 2 : 0),
      y =
          (d.canvas['y'] as num).toDouble() +
          (center ? ((d.canvas['height'] as num) - height) / 2 : 0),
      b = documentBounds(d);
  // An imported layout may already extend beyond its original boundary.
  // Expanding that boundary cannot clip any previously visible content.
  final containsPreviousCanvas =
      x <= (d.canvas['x'] as num) &&
      y <= (d.canvas['y'] as num) &&
      x + width >= (d.canvas['x'] as num) + (d.canvas['width'] as num) &&
      y + height >= (d.canvas['y'] as num) + (d.canvas['height'] as num);
  if (!containsPreviousCanvas &&
      d.nodes.isNotEmpty &&
      (b['x']! < x ||
          b['y']! < y ||
          b['x']! + b['width']! > x + width ||
          b['y']! + b['height']! > y + height))
    throw StateError('Canvas would clip objects');
  return d.copyWith(
    canvas: {...d.canvas, 'x': x, 'y': y, 'width': width, 'height': height},
  );
}

// Spreadsheet-style letters keep long rows unique beyond Z.
String _rowSeatLabel(int row, int column) {
  var n = column + 1;
  var letter = '';
  while (n > 0) {
    n--;
    letter = String.fromCharCode(65 + n % 26) + letter;
    n ~/= 26;
  }
  return '${row + 1}$letter';
}

VenueLayoutDocument rowLayout({
  int rows = 5,
  int seatsPerRow = 8,
  int blocks = 1,
  double aisle = 80,
  double spacing = 56,
  double rowSpacing = 64,
  double x = 100,
  double y = 100,
  double arc = 0,
  String? id,
  TableSeating seating = const TableSeating(),
}) {
  if (rows < 1 ||
      seatsPerRow < 1 ||
      blocks < 1 ||
      rows * seatsPerRow * blocks > 20000)
    throw ArgumentError('Invalid row count');
  if (!spacing.isFinite ||
      spacing <= 0 ||
      !rowSpacing.isFinite ||
      rowSpacing <= 0 ||
      !aisle.isFinite ||
      aisle < 0 ||
      !arc.isFinite ||
      !x.isFinite ||
      !y.isFinite)
    throw ArgumentError('Invalid row geometry');
  final root = id ?? newLayoutId(),
      parameters = <String, dynamic>{
        'rows': rows,
        'seatsPerRow': seatsPerRow,
        'blocks': blocks,
        'aisle': aisle,
        'spacing': spacing,
        'rowSpacing': rowSpacing,
        'arc': arc,
      };
  final nodes = <LayoutNode>[
    LayoutNode(
      id: root,
      kind: 'group',
      x: x,
      y: y,
      properties: const {},
      assembly: {'kind': 'rows', ...parameters},
      seating: seating.record,
    ),
    for (var r = 0; r < rows; r++)
      for (var b = 0; b < blocks; b++)
        for (var i = 0; i < seatsPerRow; i++)
          LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            width: seating.width,
            height: seating.height,
            parentId: root,
            x: b * (seatsPerRow * spacing + aisle) + i * spacing,
            y: r * rowSpacing + arc * pow(i - (seatsPerRow - 1) / 2, 2),
            rotation:
                atan(2 * arc * (i - (seatsPerRow - 1) / 2) / spacing) *
                180 /
                pi,
            label: _rowSeatLabel(r, b * seatsPerRow + i),
            properties: {'slot': '$r:$b:$i'},
          ),
  ];
  return VenueLayoutDocument(
    schemaVersion: 2,
    nodes: nodes,
    seatingDefaults: seating.record,
    attachments: [
      for (final node in nodes.where((node) => node.kind == 'seat'))
        {
          'seatId': node.id,
          'targetId': root,
          'rotationMode': 'auto',
          'placement': {'mode': 'automatic'},
        },
    ],
  );
}

/// Reads the validated stored row specification.
Map<String, num> rowLayoutParameters(VenueLayoutDocument d, String rootId) {
  final root = d.nodes.firstWhere((n) => n.id == rootId);
  {
    final spec = root.assembly;
    const fields = [
      'rows',
      'seatsPerRow',
      'blocks',
      'aisle',
      'spacing',
      'rowSpacing',
      'arc',
    ];
    if (spec?['kind'] != 'rows' || fields.any((field) => spec![field] is! num))
      throw const FormatException('incomplete_row_assembly');
    return {for (final field in fields) field: spec![field] as num};
  }
}

class LayoutFitResult {
  final VenueLayoutDocument document;
  final int placed, unplaced;
  final bool complete;
  final List<String> reasons;
  const LayoutFitResult(
    this.document,
    this.placed,
    this.unplaced,
    this.complete,
    this.reasons,
  );
}

class _SeatFitSearch {
  final VenueLayoutDocument document;
  final Map<String, double> area;
  final int count;
  final double spacing, rowSpacing;
  final List<List<double>>? boundary;
  final bool Function()? cancelled;
  late final LayoutSpatialIndex index = spatialIndexFor(document);
  late final Map<String, LayoutNode> nodes = {
    for (final n in document.nodes) n.id: n,
  };
  final added = <LayoutNode>[];
  int tried = 0;
  int budget = layoutLimits['fitCandidatesMax']!.toInt();
  bool complete = true;
  _SeatFitSearch(
    this.document,
    this.area,
    this.count,
    this.spacing,
    this.rowSpacing,
    this.boundary,
    this.cancelled,
  ) {
    if (spacing < 40 ||
        rowSpacing < 40 ||
        count < 0 ||
        [spacing, rowSpacing, ...area.values].any((v) => !v.isFinite))
      throw ArgumentError('Invalid fitting dimensions');
  }
  Iterable<void> run() sync* {
    for (
      var y = area['y']! + 20;
      y <= area['y']! + area['height']! - 20;
      y += rowSpacing
    ) {
      for (
        var x = area['x']! + 20;
        x <= area['x']! + area['width']! - 20;
        x += spacing
      ) {
        if (added.length == count) return;
        if (tried >= budget || cancelled?.call() == true) {
          complete = false;
          return;
        }
        tried++;
        final n = LayoutNode(
              id: newLayoutId(),
              kind: 'seat',
              x: x,
              y: y,
              label: '${added.length + 1}',
              style: {
                'label': {'size': 12, 'align': 'center'},
              },
            ),
            hull = worldHull(n, localMatrix(n));
        var blocked = boundary != null && !polygonContainsHull(boundary!, hull);
        if (!blocked) {
          for (final id in index.query(boundsOfPoints(hull))) {
            final other = nodes[id]!;
            if (other.kind != 'seat' &&
                other.kind != 'table' &&
                other.kind != 'furniture' &&
                other.properties['obstacle'] != true &&
                other.properties['role'] != 'obstacle')
              continue;
            if (polygonsOverlap(hull, worldHull(other, index.matrices[id]!))) {
              blocked = true;
              break;
            }
          }
        }
        // Grid steps guarantee no candidate-to-candidate overlap without resizing seats.
        if (!blocked) added.add(n);
        yield null;
      }
    }
  }

  LayoutFitResult result() => LayoutFitResult(
    document.copyWith(nodes: [...document.nodes, ...added]),
    added.length,
    count - added.length,
    complete,
    !complete
        ? ['Search interrupted; best result so far']
        : added.length < count
        ? ['Area or obstacles prevent remaining seats']
        : [],
  );
}

LayoutFitResult fitSeats(
  VenueLayoutDocument d, {
  required Map<String, double> area,
  int count = 20,
  double spacing = 56,
  double rowSpacing = 64,
  List<List<double>>? boundary,
  bool Function()? cancelled,
}) {
  final search = _SeatFitSearch(
    d,
    area,
    count,
    spacing,
    rowSpacing,
    boundary,
    cancelled,
  );
  for (final _ in search.run()) {}
  return search.result();
}

/// Yield between bounded 8ms batches so a UI cancellation can be delivered.
Future<LayoutFitResult> fitSeatsAsync(
  VenueLayoutDocument d, {
  required Map<String, double> area,
  int count = 20,
  double spacing = 56,
  double rowSpacing = 64,
  List<List<double>>? boundary,
  bool Function()? cancelled,
}) async {
  final search = _SeatFitSearch(
        d,
        area,
        count,
        spacing,
        rowSpacing,
        boundary,
        cancelled,
      ),
      watch = Stopwatch()..start();
  for (final _ in search.run()) {
    if (watch.elapsedMicroseconds >= layoutLimits['fitBatchMicroseconds']!) {
      await Future<void>.delayed(Duration.zero);
      watch.reset();
    }
  }
  return search.result();
}

VenueLayoutDocument savePreset(
  VenueLayoutDocument d,
  Set<String> ids,
  String title,
) {
  final validation = validateDocument(d);
  if (validation.isNotEmpty)
    throw InvalidLayoutDocument(validation, d.toJson());
  final selected = layoutSubtree(d, ids);
  for (final unit in d.selectionUnits) {
    final members = (unit['nodeIds'] as List).cast<String>();
    if (members.any(selected.contains) && !members.every(selected.contains))
      throw StateError('Preset would split an atomic selection unit');
  }
  final matrices = worldMatrices(d);
  final subtree = layoutSubtree(d, ids),
      fragment = d.copyWith(
        nodes: d.nodes
            .where((n) => subtree.contains(n.id))
            .map(
              (n) => subtree.contains(n.parentId)
                  ? n
                  : n.copyWith(
                      clearParent: true,
                      x: matrices[n.id]![4],
                      y: matrices[n.id]![5],
                      rotation:
                          atan2(matrices[n.id]![1], matrices[n.id]![0]) *
                          180 /
                          pi,
                    ),
            )
            .toList(),
        selectionUnits: d.selectionUnits
            .where((u) => (u['nodeIds'] as List).every(subtree.contains))
            .toList(),
        attachments: d.attachments
            .where(
              (a) =>
                  subtree.contains(a['seatId']) &&
                  subtree.contains(a['targetId']),
            )
            .toList(),
        presets: [],
        sections: [],
        clearBackground: true,
      );
  return d.copyWith(
    presets: [
      ...d.presets,
      {'id': newLayoutId(), 'title': title, 'document': fragment.toJson()},
    ],
  );
}

VenueLayoutDocument instantiatePreset(
  VenueLayoutDocument d,
  String presetId, {
  double x = 0,
  double y = 0,
}) {
  final preset = d.presets.firstWhere((p) => p['id'] == presetId),
      fragment = cloneLayout(
        VenueLayoutDocument.fromJson(
          Map<String, dynamic>.from(preset['document']),
        ),
        dx: x,
        dy: y,
      );
  return d.copyWith(
    nodes: [...d.nodes, ...fragment.nodes],
    selectionUnits: [...d.selectionUnits, ...fragment.selectionUnits],
    attachments: [...d.attachments, ...fragment.attachments],
  );
}

VenueLayoutDocument renumberSeats(
  VenueLayoutDocument d,
  List<String> ids, {
  String prefix = '',
  int start = 1,
  int step = 1,
  List<String>? labels,
}) {
  if (labels != null && labels.length != ids.length)
    throw ArgumentError('Explicit labels must match seats');
  final values = {
    for (var i = 0; i < ids.length; i++)
      ids[i]: labels?[i] ?? '$prefix${start + i * step}',
  };
  return d.copyWith(
    nodes: d.nodes
        .map(
          (n) => values.containsKey(n.id) ? n.copyWith(label: values[n.id]) : n,
        )
        .toList(),
  );
}

VenueLayoutDocument reconcileAssembly(
  VenueLayoutDocument d,
  String rootId,
  VenueLayoutDocument generated,
) {
  {
    {}
    final root = d.nodes.firstWhere((node) => node.id == rootId),
        source = generated.nodes.firstWhere((node) => node.parentId == null);
    if (root.assembly?['kind'] != 'rows' || source.assembly?['kind'] != 'rows')
      throw ArgumentError('Expected row assemblies');
    _unlocked(d, {rootId});
    final old = d.nodes.where((node) => node.parentId == rootId).toList(),
        bySlot = {
          for (final node in d.nodes.where((node) => node.parentId == rootId))
            node.properties['slot']: node,
        };
    final replacements = <LayoutNode>[], used = <String>{};
    for (final candidate in generated.nodes.where(
      (node) => node.parentId == source.id,
    )) {
      final existing = bySlot[candidate.properties['slot']];
      if (existing == null) {
        replacements.add(candidate.copyWith(parentId: rootId));
        continue;
      }
      used.add(existing.id);
      if (existing.locked) {
        replacements.add(existing);
        continue;
      }
      final free = seatPlacementFree(d, existing);
      final slot = '${candidate.properties['slot']}'
          .split(':')
          .map(int.parse)
          .toList();
      final oldColumns = (root.assembly!['seatsPerRow'] as num).toInt();
      final automaticLabel = _rowSeatLabel(
        slot[0],
        slot[1] * oldColumns + slot[2],
      );
      replacements.add(
        existing.copyWith(
          label: existing.label == automaticLabel
              ? candidate.label
              : existing.label,
          x: free ? existing.x : candidate.x,
          y: free ? existing.y : candidate.y,
          rotation: seatRotationManual(d, existing)
              ? existing.rotation
              : candidate.rotation,
          properties: {...existing.properties, ...candidate.properties},
        ),
      );
    }
    for (final node in old.where((node) => !used.contains(node.id))) {
      if (node.kind != 'seat' || seatPlacementFree(d, node)) {
        replacements.add(node);
        continue;
      }
      if (node.locked)
        throw StateError('Assembly change would remove locked seat');
    }
    final oldIds = old.map((node) => node.id).toSet(),
        kept = replacements.map((node) => node.id).toSet(),
        removed = old
            .map((node) => node.id)
            .where((id) => !kept.contains(id))
            .toSet();
    final units = <Map<String, dynamic>>[];
    for (final unit in d.selectionUnits) {
      final ids = (unit['nodeIds'] as List).cast<String>();
      if (ids.any(removed.contains)) {
        if (!ids.every(removed.contains))
          throw StateError('atomic_unit_requires_full_change');
      } else {
        units.add(unit);
      }
    }
    final anchors = {
      for (final attachment in d.attachments) attachment['seatId']: attachment,
    };
    return d.copyWith(
      nodes: [
        for (final node in d.nodes)
          if (!oldIds.contains(node.id))
            node.id == rootId
                ? node.copyWith(
                    properties: {...root.properties, ...source.properties},
                    assembly: source.assembly,
                  )
                : node,
        ...replacements,
      ],
      selectionUnits: units,
      attachments: [
        for (final attachment in d.attachments)
          if (!oldIds.contains(attachment['seatId'])) attachment,
        for (final node in replacements.where((node) => node.kind == 'seat'))
          anchors[node.id] ??
              {
                'seatId': node.id,
                'targetId': rootId,
                'rotationMode': 'auto',
                'placement': {'mode': 'automatic'},
              },
      ],
    );
  }
}

class LayoutSnapResult {
  final double dx, dy;
  final List<Map<String, dynamic>> guides;
  final String? magnet;
  const LayoutSnapResult(this.dx, this.dy, this.guides, this.magnet);
}

LayoutSnapResult snapTranslation(
  VenueLayoutDocument d,
  Set<String> ids,
  double dx,
  double dy, {
  double zoom = 1,
  double? grid,
  String? previousMagnet,
  double? axisRotation,
  bool disabled = false,
  Map<String, double>? sourceBounds,
}) {
  if (disabled) return LayoutSnapResult(dx, dy, [], null);
  if (!zoom.isFinite || zoom <= 0) throw ArgumentError('Zoom must be positive');
  final moving = layoutSubtree(d, ids),
      matrices = worldMatrices(d),
      byId = {for (final n in d.nodes) n.id: n};
  final parents = ids.map((id) => byId[id]?.parentId).toSet();
  final tableBodies =
      ids.isNotEmpty && ids.every((id) => byId[id]?.kind == 'table');
  final parent = parents.length == 1 ? byId[parents.first] : null;
  final angle =
          (axisRotation ??
              (isRowAssemblyNode(parent)
                  ? atan2(matrices[parent!.id]![1], matrices[parent.id]![0]) *
                        180 /
                        pi
                  : 0)) *
          pi /
          180,
      c = cos(angle),
      s = sin(angle);
  final frame = <double>[c, -s, s, c, 0, 0];
  final delta = transformPoint(frame, dx, dy);
  dx = delta[0];
  dy = delta[1];
  final worldPoints = d.nodes
          .where(
            (n) => tableBodies ? ids.contains(n.id) : moving.contains(n.id),
          )
          .expand((n) => worldHull(n, matrices[n.id]!))
          .toList(),
      source =
          sourceBounds ??
          boundsOfPoints(
            worldPoints.map((p) => transformPoint(frame, p[0], p[1])).toList(),
          );
  final targets =
      d.nodes
          .where(
            (n) =>
                !moving.contains(n.id) &&
                n.kind != 'group' &&
                !(tableBodies &&
                    n.kind == 'seat' &&
                    byId[n.parentId]?.kind == 'table'),
          )
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  var bestX = double.infinity, bestY = double.infinity;
  String? keyX, keyY;
  double? lineX, lineY;
  double? spacingX, spacingY;
  final canvasX = (d.canvas['x'] as num? ?? 0).toDouble();
  final canvasY = (d.canvas['y'] as num? ?? 0).toDouble();
  final canvasWidth = (d.canvas['width'] as num).toDouble();
  final canvasHeight = (d.canvas['height'] as num).toDouble();
  final targetBounds = <(String, Map<String, double>)>[
    if (angle.abs() < 1e-9)
      (
        'canvas',
        {
          'x': canvasX,
          'y': canvasY,
          'width': canvasWidth,
          'height': canvasHeight,
        },
      ),
    for (final n in targets)
      (
        n.id,
        boundsOfPoints(
          worldHull(
            n,
            matrices[n.id]!,
          ).map((p) => transformPoint(frame, p[0], p[1])).toList(),
        ),
      ),
  ];
  for (final (targetId, b) in targetBounds) {
    for (final axis in ['x', 'y']) {
      final dim = axis == 'x' ? 'width' : 'height',
          delta = axis == 'x' ? dx : dy;
      for (var a = 0; a < 3; a++) {
        for (var t = 0; t < 3; t++) {
          final from = source[axis]! + source[dim]! * a / 2 + delta,
              to = b[axis]! + b[dim]! * t / 2,
              error = to - from,
              key = '$targetId:$axis:$a:$t',
              threshold = (key == previousMagnet ? 10 : 7) / zoom;
          if (error.abs() <= threshold &&
              (axis == 'x'
                  ? error.abs() < bestX.abs()
                  : error.abs() < bestY.abs())) {
            if (axis == 'x') {
              bestX = error;
              keyX = key;
              lineX = to;
            } else {
              bestY = error;
              keyY = key;
              lineY = to;
            }
          }
        }
      }
    }
  }
  // A pair of consecutive table bodies defines a reusable edge gap. Only
  // consider the row/column currently under the moving table, so an unrelated
  // row elsewhere in the hall cannot attract it to an accidental interval.
  if (sourceBounds == null && tableBodies && ids.length == 1) {
    final tableBounds = targetBounds
        .where((target) => byId[target.$1]?.kind == 'table')
        .toList();
    for (final axis in ['x', 'y']) {
      final cross = axis == 'x' ? 'y' : 'x',
          dim = axis == 'x' ? 'width' : 'height',
          crossDim = axis == 'x' ? 'height' : 'width',
          delta = axis == 'x' ? dx : dy,
          crossDelta = axis == 'x' ? dy : dx,
          crossCenter = source[cross]! + source[crossDim]! / 2 + crossDelta,
          alignmentTolerance = 7 / zoom;
      final row =
          tableBounds
              .where(
                (target) =>
                    (target.$2[cross]! + target.$2[crossDim]! / 2 - crossCenter)
                        .abs() <=
                    alignmentTolerance,
              )
              .toList()
            ..sort((a, b) {
              final order = a.$2[axis]!.compareTo(b.$2[axis]!);
              return order != 0 ? order : a.$1.compareTo(b.$1);
            });
      for (var i = 0; i + 1 < row.length; i++) {
        final (firstId, first) = row[i];
        final (secondId, second) = row[i + 1];
        final firstCenter = first[cross]! + first[crossDim]! / 2,
            secondCenter = second[cross]! + second[crossDim]! / 2;
        if ((firstCenter - secondCenter).abs() > alignmentTolerance) continue;
        final end = first[axis]! + first[dim]!, gap = second[axis]! - end;
        if (gap < 0) continue;
        final positions = <(String, double, double)>[
          ('before', first[axis]! - gap - source[dim]!, gap),
          ('after', second[axis]! + second[dim]! + gap, gap),
          if (gap >= source[dim]!)
            (
              'between',
              end + (gap - source[dim]!) / 2,
              (gap - source[dim]!) / 2,
            ),
        ];
        for (final (position, start, spacing) in positions) {
          if (row.any(
            (target) =>
                start < target.$2[axis]! + target.$2[dim]! - 1e-7 &&
                start + source[dim]! > target.$2[axis]! + 1e-7,
          ))
            continue;
          final error = start - source[axis]! - delta,
              key = 'spacing:$firstId:$secondId:$axis:$position',
              threshold = (key == previousMagnet ? 10 : 7) / zoom;
          if (error.abs() > threshold ||
              error.abs() >= (axis == 'x' ? bestX.abs() : bestY.abs()))
            continue;
          if (axis == 'x') {
            bestX = error;
            keyX = key;
            lineX = start + source[dim]! / 2;
            spacingX = spacing;
          } else {
            bestY = error;
            keyY = key;
            lineY = start + source[dim]! / 2;
            spacingY = spacing;
          }
        }
      }
    }
  }
  if (grid != null && grid.isFinite && grid > 0) {
    // Grid is a gentle fallback, never a stronger magnet than actual objects
    // or their spacing. Do not quantize every pointer update to a coarse step.
    final threshold = min(2 / zoom, grid * .2);
    if (!bestX.isFinite) {
      final error =
          ((source['x']! + dx) / grid).round() * grid - source['x']! - dx;
      if (error.abs() <= threshold) bestX = error;
    }
    if (!bestY.isFinite) {
      final error =
          ((source['y']! + dy) / grid).round() * grid - source['y']! - dy;
      if (error.abs() <= threshold) bestY = error;
    }
  }
  final snapped = transformPoint(
    [c, s, -s, c, 0, 0],
    dx + (bestX.isFinite ? bestX : 0),
    dy + (bestY.isFinite ? bestY : 0),
  );
  return LayoutSnapResult(quantize(snapped[0]), quantize(snapped[1]), [
    if (lineX != null)
      {
        'axis': 'x',
        'value': lineX,
        'rotation': angle * 180 / pi,
        if (spacingX != null) 'kind': 'spacing',
        if (spacingX != null) 'spacing': spacingX,
      },
    if (lineY != null)
      {
        'axis': 'y',
        'value': lineY,
        'rotation': angle * 180 / pi,
        if (spacingY != null) 'kind': 'spacing',
        if (spacingY != null) 'spacing': spacingY,
      },
  ], keyX ?? keyY);
}

/// Snap the dragged edge/corner in the object's axes. The opposite edge stays
/// fixed, and the moving subtree never attracts its own resize handle.
({double width, double height, List<Map<String, dynamic>> guides}) snapResize(
  VenueLayoutDocument document,
  LayoutNode node,
  double width,
  double height, {
  required double sx,
  required double sy,
  double zoom = 1,
  double? grid,
  bool disabled = false,
  Map<String, double>? localBounds,
}) {
  if (disabled) return (width: width, height: height, guides: const []);
  final matrix = worldMatrix(document, node);
  final angle = atan2(matrix[1], matrix[0]);
  final frame = [cos(angle), -sin(angle), sin(angle), cos(angle), 0.0, 0.0];
  final point = transformPoint(
    matrix,
    (localBounds == null ? 0 : localBounds['x']! + localBounds['width']! / 2) +
        sx * (width - (localBounds?['width'] ?? node.width) / 2),
    (localBounds == null ? 0 : localBounds['y']! + localBounds['height']! / 2) +
        sy * (height - (localBounds?['height'] ?? node.height) / 2),
  );
  final local = transformPoint(frame, point[0], point[1]);
  final result = snapTranslation(
    document,
    {node.id},
    0,
    0,
    zoom: zoom,
    grid: grid,
    axisRotation: angle * 180 / pi,
    sourceBounds: {'x': local[0], 'y': local[1], 'width': 0, 'height': 0},
  );
  final delta = transformPoint(frame, result.dx, result.dy);
  return (
    width: max(1.0, width + sx * delta[0]),
    height: max(1.0, height + sy * delta[1]),
    guides: result.guides
        .where((g) => g['axis'] == 'x' ? sx != 0 : sy != 0)
        .toList(),
  );
}

class LayoutFitVariant {
  final LayoutFitResult result;
  final double spacing, rowSpacing, deviation;
  final String key;
  const LayoutFitVariant(
    this.result,
    this.spacing,
    this.rowSpacing,
    this.deviation,
    this.key,
  );
}

class LayoutFitVariants {
  final List<LayoutFitVariant> variants;
  final bool complete;
  final int tried;
  const LayoutFitVariants(this.variants, this.complete, this.tried);
}

Future<LayoutFitVariants> fitSeatVariantsAsync(
  VenueLayoutDocument d, {
  required Map<String, double> area,
  int count = 20,
  double spacing = 56,
  double rowSpacing = 64,
  double? minSpacing,
  double? maxSpacing,
  double spacingStep = 4,
  double? minRowSpacing,
  double? maxRowSpacing,
  double rowSpacingStep = 4,
  List<List<double>>? boundary,
  bool Function()? cancelled,
}) async {
  if (spacingStep <= 0 || rowSpacingStep <= 0)
    throw ArgumentError('Sampling steps must be positive');
  final minS = max(40, minSpacing ?? spacing - 8),
      maxS = maxSpacing ?? spacing + 8,
      minR = max(40, minRowSpacing ?? rowSpacing - 8),
      maxR = maxRowSpacing ?? rowSpacing + 8;
  if (maxS < minS ||
      maxR < minR ||
      [
        minS,
        maxS,
        minR,
        maxR,
        spacingStep,
        rowSpacingStep,
      ].any((v) => !v.isFinite))
    throw ArgumentError('Invalid spacing interval');
  final samples = <List<double>>[];
  for (var s = minS; s <= maxS + 1e-7; s += spacingStep) {
    for (var r = minR; r <= maxR + 1e-7; r += rowSpacingStep) {
      samples.add([s.toDouble(), r.toDouble()]);
      if (samples.length > layoutLimits['fitCandidatesMax']!)
        throw ArgumentError('Spacing sample limit');
    }
  }
  samples.sort((a, b) {
    final da = (a[0] - spacing).abs() + (a[1] - rowSpacing).abs(),
        db = (b[0] - spacing).abs() + (b[1] - rowSpacing).abs(),
        cmp = da.compareTo(db);
    return cmp != 0
        ? cmp
        : a[0] != b[0]
        ? a[0].compareTo(b[0])
        : a[1].compareTo(b[1]);
  });
  final variants = <LayoutFitVariant>[], watch = Stopwatch()..start();
  var tried = 0, complete = true;
  for (final sample in samples) {
    if (tried >= layoutLimits['fitCandidatesMax']! ||
        cancelled?.call() == true) {
      complete = false;
      break;
    }
    final search = _SeatFitSearch(
      d,
      area,
      count,
      sample[0],
      sample[1],
      boundary,
      cancelled,
    )..budget = layoutLimits['fitCandidatesMax']!.toInt() - tried;
    for (final _ in search.run()) {
      if (watch.elapsedMicroseconds >= layoutLimits['fitBatchMicroseconds']!) {
        await Future<void>.delayed(Duration.zero);
        watch.reset();
      }
    }
    tried += search.tried;
    complete = complete && search.complete;
    final deviation =
        (sample[0] - spacing).abs() + (sample[1] - rowSpacing).abs();
    variants.add(
      LayoutFitVariant(
        search.result(),
        sample[0],
        sample[1],
        deviation,
        '${sample[0]}:${sample[1]}',
      ),
    );
    if (!complete) break;
  }
  variants.sort((a, b) {
    final placed = b.result.placed.compareTo(a.result.placed);
    if (placed != 0) return placed;
    final delta = a.deviation.compareTo(b.deviation);
    return delta != 0 ? delta : a.key.compareTo(b.key);
  });
  return LayoutFitVariants(List.unmodifiable(variants), complete, tried);
}

List<LayoutNode> _selectionRoots(VenueLayoutDocument d, Set<String> ids) {
  final nodes = {for (final n in d.nodes) n.id: n};
  return d.nodes.where((n) {
    if (!ids.contains(n.id)) return false;
    var p = nodes[n.parentId];
    while (p != null) {
      if (ids.contains(p.id)) return false;
      p = nodes[p.parentId];
    }
    return true;
  }).toList();
}

VenueLayoutDocument alignNodes(
  VenueLayoutDocument d,
  Set<String> ids,
  String alignment,
) {
  if (!const [
    'left',
    'right',
    'top',
    'bottom',
    'centerX',
    'centerY',
  ].contains(alignment))
    throw ArgumentError('Unknown alignment');
  _unlocked(d, ids);
  final roots = _selectionRoots(d, ids);
  if (roots.length < 2) return d;
  final bounds = {
        for (final n in roots) n.id: selectionBounds(d, {n.id}),
      },
      all = boundsOfPoints(
        bounds.values
            .expand(
              (b) => <List<double>>[
                [b['x']!, b['y']!],
                [b['x']! + b['width']!, b['y']! + b['height']!],
              ],
            )
            .toList(),
      );
  var result = d;
  for (final n in roots) {
    final b = bounds[n.id]!;
    final dx = switch (alignment) {
          'left' => all['x']! - b['x']!,
          'right' => all['x']! + all['width']! - b['x']! - b['width']!,
          'centerX' =>
            all['x']! + all['width']! / 2 - b['x']! - b['width']! / 2,
          _ => 0.0,
        },
        dy = switch (alignment) {
          'top' => all['y']! - b['y']!,
          'bottom' => all['y']! + all['height']! - b['y']! - b['height']!,
          'centerY' =>
            all['y']! + all['height']! / 2 - b['y']! - b['height']! / 2,
          _ => 0.0,
        };
    result = transformNodes(result, {n.id}, dx: dx, dy: dy);
  }
  return result;
}

VenueLayoutDocument distributeNodes(
  VenueLayoutDocument d,
  Set<String> ids, {
  bool horizontal = true,
}) {
  _unlocked(d, ids);
  final roots = _selectionRoots(d, ids);
  if (roots.length < 3) return d;
  final axis = horizontal ? 'x' : 'y',
      dimension = horizontal ? 'width' : 'height',
      bounds = {
        for (final n in roots) n.id: selectionBounds(d, {n.id}),
      };
  roots.sort((a, b) {
    final c = bounds[a.id]![axis]!.compareTo(bounds[b.id]![axis]!);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  final first = bounds[roots.first.id]!,
      last = bounds[roots.last.id]!,
      span = last[axis]! + last[dimension]! - first[axis]!,
      total = roots.fold<double>(
        0,
        (sum, n) => sum + bounds[n.id]![dimension]!,
      ),
      gap = (span - total) / (roots.length - 1);
  var cursor = first[axis]!, result = d;
  for (final n in roots) {
    final b = bounds[n.id]!, delta = cursor - b[axis]!;
    result = transformNodes(
      result,
      {n.id},
      dx: horizontal ? delta : 0,
      dy: horizontal ? 0 : delta,
    );
    cursor += b[dimension]! + gap;
  }
  return result;
}

VenueLayoutDocument reorderNodes(
  VenueLayoutDocument d,
  Set<String> ids,
  int direction,
) {
  _unlocked(d, ids);
  return reorderLayoutLayers(d, ids, direction: direction);
}

String _barSide(LayoutNode node) {
  final side = node.properties['guestSide'];
  if (!isBarNode(node) || !barGuestSides.contains(side)) {
    throw ArgumentError('Bar guest side must be top, right, bottom or left.');
  }
  return side as String;
}

VenueLayoutDocument barLayout({
  int count = 0,
  double x = 400,
  double y = 300,
  double width = 280,
  double height = 72,
  String guestSide = 'bottom',
  String? id,

  TableSeating seating = const TableSeating(),
}) {
  if (!barGuestSides.contains(guestSide))
    throw ArgumentError('Bar guest side must be top, right, bottom or left.');
  if ([
        x,
        y,
        width,
        height,
      ].any((v) => !v.isFinite || v.abs() > layoutLimits['geometryAbsMax']!) ||
      width <= 0 ||
      height <= 0) {
    throw ArgumentError(
      'Bar dimensions and coordinates must be finite and positive.',
    );
  }
  final bar = LayoutNode(
    id: id ?? newLayoutId(),
    kind: 'table',
    x: x,
    y: y,
    width: width,
    height: height,
    surface: {'type': 'rect'},
    seating: seating.record,
    properties: {'furniture': 'bar', 'guestSide': guestSide},
  );
  return reflowTable(
    VenueLayoutDocument(schemaVersion: 2, nodes: [bar]),
    bar.id,
    count,
  );
}

int barSeatCount(VenueLayoutDocument document, String id) {
  final node = document.nodes.firstWhere((n) => n.id == id);
  _barSide(node);
  return document.nodes
      .where((n) => n.kind == 'seat' && n.parentId == id)
      .length;
}

VenueLayoutDocument reflowBar(
  VenueLayoutDocument document,
  String id,
  int count, {
  Set<String> protectedSeatIds = const {},
}) {
  _barSide(document.nodes.firstWhere((n) => n.id == id));
  final result = reflowTable(
    document,
    id,
    count,
    constrainToCanvas: true,
    protectedSeatIds: protectedSeatIds,
  );
  final issues = validateDocument(result);
  if (issues.isNotEmpty)
    throw StateError('Bar stools must stay on the guest side.');
  return result;
}

VenueLayoutDocument setBarGuestSide(
  VenueLayoutDocument document,
  String id,
  String side, {
  Set<String> protectedSeatIds = const {},
}) {
  final bar = document.nodes.firstWhere((n) => n.id == id);
  _barSide(bar);
  if (!barGuestSides.contains(side))
    throw ArgumentError('Bar guest side must be top, right, bottom or left.');
  final next = document.copyWith(
    nodes: [
      for (final node in document.nodes)
        node.id == id
            ? node.copyWith(properties: {...node.properties, 'guestSide': side})
            : node,
    ],
  );
  final count = barSeatCount(document, id);
  if (count > tableCapacity(next.nodes.firstWhere((n) => n.id == id))) {
    throw StateError('This bar side is too short for its stools.');
  }
  return reflowBar(next, id, count, protectedSeatIds: protectedSeatIds);
}

/// Change a typed surface without removing or replacing existing seat identities.
VenueLayoutDocument setTableSurfaceKind(
  VenueLayoutDocument document,
  String id,
  String kind, {
  Set<String> protectedSeatIds = const {},
}) {
  {}
  final table = document.nodes.firstWhere((node) => node.id == id),
      seats = document.nodes
          .where((node) => node.parentId == id && node.kind == 'seat')
          .toList();
  if (table.kind != 'table' ||
      !const {'rect', 'circle', 'grid'}.contains(kind) ||
      isBarNode(table) && kind == 'circle')
    throw ArgumentError('Invalid table surface');
  if (table.surface?['type'] == kind) return document;
  _unlocked(document, {id, ...seats.map((seat) => seat.id)});
  final diameter = max(table.width, table.height);
  var next = table.copyWith(
    surface: {'type': kind == 'grid' ? 'rect' : kind},
    width: kind == 'circle' ? diameter : table.width,
    height: kind == 'circle' ? diameter : table.height,
    seating: TableSeating.fromDocument(document, table).record,
  );
  if (kind == 'grid') next = snapTableSurfaceToGrid(next, preset: 'L');
  if (tableCapacity(next) < seats.length)
    throw StateError('Table capacity exceeded');
  final result = reconcileSurfaceEdit(
    document,
    document.copyWith(
      nodes: [for (final node in document.nodes) node.id == id ? next : node],
    ),
    id,
    protectedSeatIds: protectedSeatIds,
  );
  final retained = result.nodes
      .where((node) => node.parentId == id && node.kind == 'seat')
      .map((seat) => seat.id)
      .toSet();
  if (retained.length != seats.length ||
      !retained.containsAll(seats.map((seat) => seat.id)))
    throw StateError('Table capacity exceeded');
  return result;
}

/// Reconciles edited table footprints through the existing protected-seat rules.
/// Recentring a path must not move an attached manual/locked seat in world space.
VenueLayoutDocument reconcileSurfaceEdit(
  VenueLayoutDocument before,
  VenueLayoutDocument after,
  String id, {
  Set<String> protectedSeatIds = const {},
}) {
  final old = before.nodes.firstWhere((n) => n.id == id),
      next = after.nodes.firstWhere((n) => n.id == id);
  if (old.kind != 'table') return after;
  final localDelta = transformPoint(
    inverseMatrix(localMatrix(old)),
    next.x,
    next.y,
  );
  final adjusted = after.copyWith(
    attachments:
        old.surface?['type'] != 'grid' ||
            next.surface?['type'] != 'grid' ||
            old.surface?['moduleSize'] != next.surface?['moduleSize']
        ? after.attachments
        : [
            for (final attachment in after.attachments)
              if (attachment['targetId'] == id &&
                  attachment['placement']?['cell'] is List)
                {
                  ...attachment,
                  'placement': {
                    ...attachment['placement'] as Map,
                    'cell': [
                      (attachment['placement']['cell'][0] as int) +
                          (((next.width - old.width) / 2 - localDelta[0]) /
                                  (next.surface!['moduleSize'] as num))
                              .round(),
                      (attachment['placement']['cell'][1] as int) +
                          (((next.height - old.height) / 2 - localDelta[1]) /
                                  (next.surface!['moduleSize'] as num))
                              .round(),
                    ],
                  },
                }
              else
                attachment,
          ],
    nodes: [
      for (final n in after.nodes)
        n.parentId == id
            ? n.copyWith(x: n.x - localDelta[0], y: n.y - localDelta[1])
            : n,
    ],
  );
  final count = before.nodes
      .where((n) => n.parentId == id && n.kind == 'seat')
      .length;
  return reflowTable(
    adjusted,
    id,
    min(count, tableCapacity(next)),
    protectedSeatIds: protectedSeatIds,
  );
}

VenueLayoutDocument configureTableSeating(
  VenueLayoutDocument doc,
  String tableId,
  TableSeating seating, {
  Set<String> protectedSeatIds = const {},
}) {
  for (final v in [
    seating.width,
    seating.height,
    seating.gap,
    seating.spacing,
    seating.edgePadding,
  ]) {
    if (!v.isFinite || v < 0 || v > 1000000)
      throw ArgumentError('Invalid chair dimensions or spacing');
  }
  if (seating.width <= 0 || seating.height <= 0)
    throw ArgumentError('Chair dimensions must be positive');
  final seats = doc.nodes
      .where((n) => n.parentId == tableId && n.kind == 'seat')
      .toList();
  _unlocked(doc, {tableId, ...seats.map((n) => n.id)});
  final ids = seats.map((n) => n.id).toSet();
  final next = doc.copyWith(
    nodes: [
      for (final n in doc.nodes)
        if (n.id == tableId)
          n.copyWith(seating: {...n.seating, ...seating.record})
        else if (ids.contains(n.id))
          n.copyWith(
            width: seating.width,
            height: seating.height,
            properties: n.properties,
          )
        else
          n,
    ],
    attachments: [
      for (final a in doc.attachments) ids.contains(a['seatId']) ? a : a,
    ],
  );
  return reflowTable(
    next,
    tableId,
    seats.length,
    constrainToCanvas: true,
    protectedSeatIds: protectedSeatIds,
  );
}

/// Changes all unlocked table profiles in one immutable authoring operation.
/// Existing IDs, manual placements and explicit rotations are preserved.
/// The persisted default also governs tables inserted into an empty plan.
VenueLayoutDocument configurePlanTableGap(
  VenueLayoutDocument doc,
  double gap, {
  bool constrainToCanvas = true,
}) => configurePlanTableSeating(
  doc,
  gap: gap,
  constrainToCanvas: constrainToCanvas,
);

/// Applies only the supplied physical settings, preserving local values for
/// every other setting. The operation is atomic if reflow cannot fit.
VenueLayoutDocument configurePlanTableSeating(
  VenueLayoutDocument doc, {
  double? width,
  double? height,
  double? gap,
  double? spacing,
  double? edgePadding,
  bool constrainToCanvas = true,
}) {
  {
    final defaults = TableSeating.fromRecord(doc.seatingDefaults).copyWith(
      width: width,
      height: height,
      gap: gap,
      spacing: spacing,
      edgePadding: edgePadding,
    );
    for (final entry in defaults.record.entries) {
      final value = entry.value as double;
      if (!value.isFinite ||
          value > (1000000) ||
          value < (const {'width', 'height'}.contains(entry.key) ? 1 : 0))
        throw ArgumentError('Invalid chair dimensions or spacing');
    }
    var next = doc.copyWith(seatingDefaults: defaults.record);
    final byId = {for (final n in doc.nodes) n.id: n};
    bool locked(LayoutNode node) {
      LayoutNode? current = node;
      while (current != null) {
        if (current.locked) return true;
        current = byId[current.parentId];
      }
      return doc.nodes.any((n) => n.parentId == node.id && n.locked);
    }

    for (final table in doc.nodes.where(
      (n) => n.kind == 'table' && !isBarNode(n) && !locked(n),
    )) {
      final profile = TableSeating.fromDocument(doc, table).copyWith(
        width: width,
        height: height,
        gap: gap,
        spacing: spacing,
        edgePadding: edgePadding,
      );
      next = configureTableSeating(next, table.id, profile);
    }
    final issues = validateDocument(next);
    if (issues.isNotEmpty) throw InvalidLayoutDocument(issues, next.toJson());
    return next;
  }
}
