import 'dart:math' as math;

import 'model.dart';
import 'placement.dart';

/// Shared local upholstery geometry; dimensions are in document units.
const couchGeometry = <String, double>{
  'sideInset': 12,
  'backInset': 24,
  'frontInset': 12,
  'gap': 8,
  'minSeatWidth': 32,
  'minSeatHeight': 24,
};

bool isCouchNode(LayoutNode node) =>
    node.kind == 'furniture' && node.properties['furniture'] == 'couch';

class CouchResizeRejected implements Exception {
  final String couchId;
  final Set<String> protectedSeatIds;
  final String message;
  CouchResizeRejected({
    required this.couchId,
    required Set<String> protectedSeatIds,
    this.message = 'Reserved or blocked seats prevent changing this couch.',
  }) : protectedSeatIds = Set.unmodifiable(protectedSeatIds);
  @override
  String toString() => message;
}

/// A couch owns actual seat nodes and one atomic selection unit. No host state
/// or reservation metadata is persisted in this geometry document.
VenueLayoutDocument couchLayout({
  int count = 2,
  double x = 400,
  double y = 300,
  double width = 160,
  double height = 100,
  String? id,
}) {
  for (final coordinate in [x, y]) {
    if (!coordinate.isFinite ||
        coordinate.abs() > layoutLimits['geometryAbsMax']!) {
      throw ArgumentError(
        'Couch coordinates must be finite and within geometry limits',
      );
    }
  }
  final root = LayoutNode(
    id: id ?? newLayoutId(),
    kind: 'furniture',
    x: x,
    y: y,
    width: width,
    height: height,
    properties: {'furniture': 'couch', 'shape': 'roundedRect'},
    style: const {'fill': '#DED4F0FF'},
    assembly: {'kind': 'couch', 'seats': count},
  );
  return _rebuild(
    VenueLayoutDocument(schemaVersion: 2, nodes: [root]),
    root,
    const [],
    count,
    width,
    height,
  );
}

int couchSeatCount(VenueLayoutDocument document, String rootId) {
  final root = _root(document, rootId);
  return _seats(document, root).length;
}

/// Retains the existing unit ID and stable cushion slots. Any protected member
/// freezes the whole atomic membership, including additions. Root transform and
/// canvas are unchanged. Count changes preserve the current cushion width,
/// growing or shrinking the body symmetrically around its existing center.
VenueLayoutDocument resizeCouchSeats(
  VenueLayoutDocument document,
  String rootId,
  int count, {
  Set<String> protectedSeatIds = const {},
}) {
  final root = _root(document, rootId), seats = _seats(document, root);
  _count(count);
  if (count == seats.length) return document;
  final protected = seats
      .map((n) => n.id)
      .toSet()
      .intersection(protectedSeatIds);
  if (protected.isNotEmpty) {
    throw CouchResizeRejected(couchId: rootId, protectedSeatIds: protected);
  }
  _unlocked(document, root);
  final side = couchGeometry['sideInset']!, gap = couchGeometry['gap']!;
  final oldCount = math.max(1, seats.length);
  final cushionWidth = math.max(
    couchGeometry['minSeatWidth']!,
    (root.width - 2 * side - (oldCount - 1) * gap) / oldCount,
  );
  final width = 2 * side + count * cushionWidth + (count - 1) * gap;
  return _rebuild(document, root, seats, count, width, root.height);
}

/// Preserves membership and root transform, clamps to the minimum upholstery
/// dimensions and recomputes cushion rectangles. Never grows the canvas.
VenueLayoutDocument resizeCouchBody(
  VenueLayoutDocument document,
  String rootId,
  double width,
  double height, {
  Set<String> protectedSeatIds = const {},
}) {
  final root = _root(document, rootId), seats = _seats(document, root);
  _unlocked(document, root);
  return _rebuild(document, root, seats, seats.length, width, height);
}

LayoutNode _root(VenueLayoutDocument d, String id) {
  final matches = d.nodes.where((n) => n.id == id);
  if (matches.length != 1 || !isCouchNode(matches.single)) {
    throw ArgumentError.value(id, 'rootId', 'Expected one couch root');
  }
  return matches.single;
}

List<LayoutNode> _seats(VenueLayoutDocument d, LayoutNode root) =>
    d.nodes.where((n) => n.parentId == root.id && n.kind == 'seat').toList()
      ..sort((a, b) {
        final aSlot = a.properties['slot'], bSlot = b.properties['slot'];
        if (aSlot is num && bSlot is num && aSlot != bSlot) {
          return aSlot.compareTo(bSlot);
        }
        final order = a.x.compareTo(b.x);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });

void _count(int count) {
  if (count < 1 || count > layoutMaxSeats) {
    throw RangeError.range(count, 1, layoutMaxSeats, 'count');
  }
}

void _unlocked(VenueLayoutDocument d, LayoutNode root) {
  final index = {for (final n in d.nodes) n.id: n};
  for (final node in d.nodes) {
    var current = node;
    final seen = <String>{};
    while (seen.add(current.id)) {
      if (current.id == root.id) {
        if (node.locked) throw StateError('Locked couch object ${node.id}');
        break;
      }
      final parent = index[current.parentId];
      if (parent == null) break;
      current = parent;
    }
  }
  LayoutNode? ancestor = root;
  final seen = <String>{};
  while (ancestor != null && seen.add(ancestor.id)) {
    if (ancestor.locked) throw StateError('Locked couch object ${ancestor.id}');
    ancestor = index[ancestor.parentId];
  }
}

VenueLayoutDocument _rebuild(
  VenueLayoutDocument d,
  LayoutNode root,
  List<LayoutNode> seats,
  int count,
  double width,
  double height,
) {
  _count(count);
  for (final dimension in [width, height]) {
    if (!dimension.isFinite ||
        dimension <= 0 ||
        dimension > layoutLimits['geometryAbsMax']!) {
      throw ArgumentError('Couch dimensions must be finite and positive');
    }
  }
  final side = couchGeometry['sideInset']!, gap = couchGeometry['gap']!;
  // Persist the initial physical footprint so enlarging and shrinking later
  // does not progressively change the minimum or squeeze source-scale seats.
  final minWidth =
      (((root.assembly?['minSeatWidth'])) as num?)?.toDouble() ??
      (seats.isEmpty
          ? couchGeometry['minSeatWidth']!
          : seats.map((n) => n.width).reduce(math.min));
  final minHeight =
      (((root.assembly?['minSeatHeight'])) as num?)?.toDouble() ??
      (seats.isEmpty
          ? couchGeometry['minSeatHeight']!
          : seats.map((n) => n.height).reduce(math.min));
  width = math.max(width, 2 * side + count * minWidth + (count - 1) * gap);
  height = math.max(
    height,
    couchGeometry['backInset']! + couchGeometry['frontInset']! + minHeight,
  );
  final oldIds = seats.map((n) => n.id).toSet();
  final units = d.selectionUnits
      .where((u) => (u['nodeIds'] as List).any(oldIds.contains))
      .toList();
  if (units.length > 1 ||
      units.any(
        (u) => (u['nodeIds'] as List).any((id) => !oldIds.contains(id)),
      )) {
    throw StateError('Couch seats must belong to one exclusive atomic unit');
  }
  final seatWidth = (width - 2 * side - (count - 1) * gap) / count;
  final seatHeight =
      height - couchGeometry['backInset']! - couchGeometry['frontInset']!;
  final nextSeats = <LayoutNode>[
    for (var i = 0; i < count; i++)
      (i < seats.length
              ? seats[i]
              : LayoutNode(
                  id: newLayoutId(),
                  kind: 'seat',
                  parentId: root.id,
                  label: '${i + 1}',
                  style: const {
                    'fill': '#F8FAFCFF',
                    'label': {'size': 12, 'align': 'center'},
                  },
                  properties: const {},
                ))
          .copyWith(
            x: i < seats.length && seatPlacementFree(d, seats[i])
                ? seats[i].x
                : -width / 2 + side + seatWidth / 2 + i * (seatWidth + gap),
            y: i < seats.length && seatPlacementFree(d, seats[i])
                ? seats[i].y
                : (couchGeometry['backInset']! - couchGeometry['frontInset']!) /
                      2,
            rotation: i < seats.length && seatRotationManual(d, seats[i])
                ? seats[i].rotation
                : 0,
            width: seatWidth,
            height: seatHeight,
            properties: {
              ...(i < seats.length ? seats[i].properties : const {}),
              'furniture': 'cushion',
              'shape': 'roundedRect',
              'slot': i,
            },
          ),
  ];
  final removed = oldIds.difference(nextSeats.map((n) => n.id).toSet());
  final unit = units.isEmpty
      ? <String, dynamic>{'id': newLayoutId()}
      : units.single;
  final result = d.copyWith(
    nodes: [
      for (final n in d.nodes)
        if (n.id == root.id)
          root.copyWith(
            width: width,
            height: height,
            assembly: {
              'kind': 'couch',
              'seats': count,
              'minSeatWidth': seats.isEmpty ? seatWidth : minWidth,
              'minSeatHeight': seats.isEmpty ? seatHeight : minHeight,
            },
            properties: {...root.properties},
          )
        else if (!oldIds.contains(n.id))
          n,
      ...nextSeats,
    ],
    selectionUnits: [
      ...d.selectionUnits.where((u) => u['id'] != unit['id']),
      {
        ...unit,
        'kind': 'atomic',
        'nodeIds': nextSeats.map((n) => n.id).toList(),
      },
    ],
    attachments: [
      ...d.attachments.where(
        (a) =>
            !removed.contains(a['seatId']) && !removed.contains(a['targetId']),
      ),
      for (final seat in nextSeats)
        if (!d.attachments.any((a) => a['seatId'] == seat.id))
          {
            'id': newLayoutId(),
            'seatId': seat.id,
            'targetId': root.id,
            'placement': {'mode': 'automatic'},
            'rotationMode': 'auto',
          },
    ],
  );
  final issues = validateDocument(result);
  if (issues.isNotEmpty) {
    throw InvalidLayoutDocument(issues, {
      'couchId': root.id,
      'width': width,
      'height': height,
      'count': count,
    });
  }
  return result;
}
