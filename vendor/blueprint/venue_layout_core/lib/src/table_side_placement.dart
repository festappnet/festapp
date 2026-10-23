import 'model.dart';
import 'operations.dart' show setTableSeatPlacement;
import 'geometry.dart';
import 'table_seating.dart';

const tableSeatSides = ['top', 'right', 'bottom', 'left'];

bool supportsTableSeatSides(LayoutNode table) =>
    table.kind == 'table' &&
    !isBarNode(table) &&
    table.surface?['type'] == 'rect';

/// Native imports may keep the desk and its chairs as siblings in one group.
LayoutNode? tableForSeat(VenueLayoutDocument document, LayoutNode seat) {
  final nodes = {for (final n in document.nodes) n.id: n};
  final parent = nodes[seat.parentId];
  if (parent?.kind == 'table') return parent;
  return null;
}

String? tableSideForSeat(VenueLayoutDocument document, LayoutNode seat) {
  final table = tableForSeat(document, seat);
  if (table == null || !supportsTableSeatSides(table)) return null;
  final anchor = document.attachments
      .where((a) => a['seatId'] == seat.id && a['targetId'] == table.id)
      .firstOrNull;
  if (anchor?['placement']?['mode'] == 'sidePinned') {
    return anchor!['placement']['side'] as String?;
  }
  final local = multiplyMatrix(
    inverseMatrix(worldMatrix(document, table)),
    worldMatrix(document, seat),
  );
  return local[4].abs() / table.width > local[5].abs() / table.height
      ? (local[4] < 0 ? 'left' : 'right')
      : (local[5] < 0 ? 'top' : 'bottom');
}

/// Changes the explicit side pin independently of free placement and rotation.
VenueLayoutDocument moveTableSeatToSide(
  VenueLayoutDocument document,
  String seatId,
  String side,
) {
  if (!tableSeatSides.contains(side)) throw ArgumentError('Invalid table side');
  {
    final seat = document.nodes.firstWhere((node) => node.id == seatId),
        table = tableForSeat(
          document,
          document.nodes.firstWhere((node) => node.id == seatId),
        );
    if (table == null || !supportsTableSeatSides(table)) {
      throw ArgumentError('Select a chair at a rectangular table');
    }
    final horizontal = side == 'top' || side == 'bottom';
    final length = horizontal ? table.width : table.height,
        along = horizontal ? seat.x : seat.y;
    final profile = TableSeating.fromDocument(document, table);
    final margin = ((profile.edgePadding + seat.width / 2) / length).clamp(
      0.0,
      .5,
    );
    final t = (along / length + .5).clamp(margin, 1 - margin);
    return setTableSeatPlacement(document, seatId, {
      'mode': 'sidePinned',
      'side': side,
      't': t,
    });
  }
}
