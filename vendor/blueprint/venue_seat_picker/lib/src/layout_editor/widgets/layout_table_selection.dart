import 'dart:ui';
import 'package:venue_layout_core/venue_layout_core.dart';

/// A commercial wrapper moves as one object, but its edit bounds belong to
/// the physical tabletop. Genuine multi-object groups keep their own bounds.
LayoutNode tabletopSelectionNode(VenueLayoutDocument doc, LayoutNode selected) {
  if (selected.kind != 'group' || selected.assembly != null) {
    return selected;
  }
  final children = doc.nodes
      .where((node) => node.parentId == selected.id)
      .toList();
  return children.length == 1 && children.single.kind == 'table'
      ? children.single
      : selected;
}

/// Editor-only relationships. These never become selected nodes or resize bounds.
class TableSeatLink {
  const TableSeatLink(this.seatId, this.tablePoint, this.seatPoint);
  final String seatId;
  final Offset tablePoint, seatPoint;
}

List<TableSeatLink> tableSeatLinks(
  VenueLayoutDocument doc,
  Set<String> selected,
) {
  if (selected.isEmpty) return const [];
  final targets = {for (final a in doc.attachments) a['seatId']: a['targetId']};
  final selectedSeatTables = {
    for (final n in doc.nodes)
      if (n.kind == 'seat' && selected.contains(n.id))
        targets[n.id] ?? n.parentId,
  };
  final tables = {
    for (final n in doc.nodes)
      if (n.kind == 'table' &&
          (selected.contains(n.id) || selectedSeatTables.contains(n.id)))
        n.id: n,
  };
  if (tables.isEmpty) return const [];
  final matrices = worldMatrices(doc);
  final hulls = {
    for (final t in tables.values)
      t.id: worldHull(t, matrices[t.id]!.map(quantize).toList()),
  };
  Offset nearest(List<List<double>> hull, Offset point) {
    var best = point, distance = double.infinity;
    for (var i = 0; i < hull.length; i++) {
      final a = Offset(hull[i][0], hull[i][1]),
          next = hull[(i + 1) % hull.length];
      final b = Offset(next[0], next[1]), edge = b - a;
      final t = edge.distanceSquared == 0
          ? 0.0
          : (((point - a).dx * edge.dx + (point - a).dy * edge.dy) /
                    edge.distanceSquared)
                .clamp(0.0, 1.0);
      final candidate = a + edge * t, d = (candidate - point).distanceSquared;
      if (d < distance) {
        best = candidate;
        distance = d;
      }
    }
    return best;
  }

  return [
    for (final seat in doc.nodes)
      if (seat.kind == 'seat' &&
          tables.containsKey(targets[seat.id] ?? seat.parentId) &&
          (selected.contains(seat.id) ||
              selected.contains(targets[seat.id] ?? seat.parentId)))
        (() {
          final m = matrices[seat.id]!.map(quantize).toList(),
              center = Offset(m[4], m[5]);
          final tablePoint = nearest(
            hulls[targets[seat.id] ?? seat.parentId]!,
            center,
          );
          return TableSeatLink(
            seat.id,
            tablePoint,
            nearest(worldHull(seat, m), tablePoint),
          );
        })(),
  ];
}
