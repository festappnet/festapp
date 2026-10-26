import 'seat_adapter.dart';
import 'seat_status.dart';

/// A position in the rendered grid and its current presentation state.
///
/// A slot can be empty. Selection and highlight flags are transient and do not
/// mutate the host application's seat model.
class SeatSlot<T, Id extends Object> {
  SeatSlot({
    required this.position,
    required this.size,
    this.seat,
    this.seatId,
    this.status,
    this.label,
    this.groupId,
  });

  final SeatPosition position;
  final double size;
  T? seat;
  Id? seatId;
  SeatStatus? status;
  String? label;
  Object? groupId;
  bool isSelected = false;
  bool isPending = false;
  bool isSwapHighlighted = false;
  bool isGroupHighlighted = false;
  bool isTooltipHighlighted = false;

  int get row => position.row;
  int get column => position.column;

  @override
  bool operator ==(Object other) =>
      other is SeatSlot<T, Id> && other.position == position;

  @override
  int get hashCode => position.hashCode;
}
