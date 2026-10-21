import 'dart:math';
import 'model.dart';
import 'table_seating.dart';

Map<String, dynamic>? seatAttachment(VenueLayoutDocument document, String id) =>
    document.attachments.where((a) => a['seatId'] == id).firstOrNull;
bool seatRotationManual(VenueLayoutDocument document, LayoutNode seat) {
  return seatAttachment(document, seat.id)?['rotationMode'] == 'manual';
}

bool seatPlacementFree(VenueLayoutDocument document, LayoutNode seat) {
  return seatAttachment(document, seat.id)?['placement']?['mode'] == 'free';
}

/// Recompute only explicitly pinned seats during a physical authoring command.
/// Loading, style edits and rigid moves never invoke placement.
VenueLayoutDocument reflowCanonicalPins(
  VenueLayoutDocument document,
  String tableId,
) {
  final table = document.nodes.firstWhere((n) => n.id == tableId),
      rules = TableSeating.fromDocument(
        document,
        document.nodes.firstWhere((n) => n.id == tableId),
      );
  final replacements = <String, LayoutNode>{};
  for (final attachment in document.attachments.where(
    (a) => a['targetId'] == tableId,
  )) {
    final p = attachment['placement'] as Map;
    if (p['mode'] != 'sidePinned') continue;
    final seat = document.nodes.firstWhere((n) => n.id == attachment['seatId']);
    var x = 0.0, y = 0.0, nx = 0.0, ny = 0.0;
    if (p['cell'] case final List cell) {
      if (!canonicalGridPinOnBoundary(table, cell, '${p['face']}'))
        throw StateError('invalid_grid_pin');
      final face = p['face'];
      final delta = switch (face) {
        'top' => [0, -1],
        'right' => [1, 0],
        'bottom' => [0, 1],
        _ => [-1, 0],
      };
      nx = delta[0].toDouble();
      ny = delta[1].toDouble();
      final module = (table.surface!['moduleSize'] as num).toDouble();
      x = ((cell[0] as num) + .5 + nx * .5) * module - table.width / 2;
      y = ((cell[1] as num) + .5 + ny * .5) * module - table.height / 2;
    } else {
      final side = p['side'], t = (p['t'] as num).toDouble();
      if (side == 'perimeter' && table.surface?['type'] == 'circle') {
        final angle = t * pi * 2;
        nx = cos(angle);
        ny = sin(angle);
        x = nx * table.width / 2;
        y = ny * table.height / 2;
      } else {
        if (table.surface?['type'] != 'rect' || side == 'perimeter')
          throw StateError('invalid_surface_pin');
        nx = side == 'left'
            ? -1
            : side == 'right'
            ? 1
            : 0;
        ny = side == 'top'
            ? -1
            : side == 'bottom'
            ? 1
            : 0;
        x = nx == 0 ? (t - .5) * table.width : nx * table.width / 2;
        y = ny == 0 ? (t - .5) * table.height : ny * table.height / 2;
      }
    }
    x += nx * (seat.height / 2 + rules.gap);
    y += ny * (seat.height / 2 + rules.gap);
    final next = seat.copyWith(
      x: quantize(x),
      y: quantize(y),
      rotation: attachment['rotationMode'] == 'manual'
          ? seat.rotation
          : quantize(atan2(-nx, ny) * 180 / pi),
    );
    if (seat.locked && !sameLayoutNode(seat, next))
      throw StateError('locked_seat');
    replacements[seat.id] = next;
  }
  return replacements.isEmpty
      ? document
      : document.copyWith(
          nodes: [
            for (final node in document.nodes) replacements[node.id] ?? node,
          ],
        );
}
