import 'dart:math' as math;
import 'package:venue_layout_core/venue_layout_core.dart';

// Existing V1 seat visual: 100-unit cell, 11.25-unit inset and 20-unit radius.
const referenceHallSeatSize = 77.5;
const referenceHallSeatStyle = <String, dynamic>{
  'material': 'simple',
  'seatStyle': 'plain',
  'fill': '#267329FF',
  'stroke': '#00000000',
  'strokeWidth': 0,
  'cornerRadius': 20,
};

/// Preserve source labels and world coordinates with fresh editable identities.
void addReferenceHallSeats({
  required List<LayoutNode> nodes,
  required List<Map<String, dynamic>> attachments,
  required Map<int, LayoutNode> tables,
  required List<(int, String, int, int)> seats,
}) {
  final slots = <int, int>{};
  for (final r in seats) {
    final table = tables[r.$1]!;
    final worldX = (r.$3 + .5) * 100 - table.x;
    final worldY = (r.$4 + .5) * 100 - table.y;
    final angle = -table.rotation * math.pi / 180;
    final x = worldX * math.cos(angle) - worldY * math.sin(angle);
    final y = worldX * math.sin(angle) + worldY * math.cos(angle);
    final horizontalSide =
        x.abs() / (table.width / 2) > y.abs() / (table.height / 2);
    final edge = horizontalSide
        ? (x < 0 ? 'left' : 'right')
        : (y < 0 ? 'top' : 'bottom');
    final rotation = <String, double>{
      'left': 90,
      'right': 270,
      'top': 180,
      'bottom': 0,
    }[edge]!;
    final id = newLayoutId();
    nodes.add(
      LayoutNode(
        id: id,
        kind: 'seat',
        parentId: table.id,
        x: x,
        y: y,
        width: referenceHallSeatSize,
        height: referenceHallSeatSize,
        rotation: rotation,
        label: r.$2,
        properties: {
          'symbol': 'chair',
          'slot': slots.update(r.$1, (v) => v + 1, ifAbsent: () => 0),
        },
      ),
    );
    attachments.add({
      'id': newLayoutId(),
      'seatId': id,
      'targetId': table.id,
      'placement': {'mode': 'free'},
      'rotationMode': 'manual',
    });
  }
}
