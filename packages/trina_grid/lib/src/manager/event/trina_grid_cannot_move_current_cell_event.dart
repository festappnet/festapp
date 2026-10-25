import 'package:trina_grid/trina_grid.dart';

/// Occurs when the keyboard hits the end of the grid.
class TrinaGridCannotMoveCurrentCellEvent extends TrinaGridEvent {
  /// The position of the cell when it hits.
  final TrinaGridCellPosition cellPosition;

  /// The direction to move.
  final TrinaMoveDirection direction;

  TrinaGridCannotMoveCurrentCellEvent({
    required this.cellPosition,
    required this.direction,
  }) : super();

  @override
  void handler(TrinaGridStateManager stateManager) {}
}
