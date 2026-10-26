import 'seat_status.dart';

/// Zero-based position of a seat inside a venue grid.
class SeatPosition {
  const SeatPosition(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      other is SeatPosition && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => '($row, $column)';
}

/// Read-only projection from an application's domain model into the picker.
///
/// The package never mutates [T]. Authoritative changes stay in the host
/// application and can be applied by loading or replacing seats again.
class SeatAdapter<T, Id extends Object> {
  const SeatAdapter({
    required this.idOf,
    required this.positionOf,
    required this.statusOf,
    this.labelOf,
    this.groupOf,
  });

  final Id Function(T seat) idOf;
  final SeatPosition Function(T seat) positionOf;
  final SeatStatus Function(T seat) statusOf;
  final String? Function(T seat)? labelOf;
  final Object? Function(T seat)? groupOf;
}
