/// Authoritative availability of a seat.
///
/// The current visitor's selection is deliberately not a status. It is an
/// optimistic presentation overlay owned by the picker.
enum SeatStatus {
  /// The seat can be selected.
  available,

  /// The seat is temporarily held by another visitor.
  held,

  /// The seat has been booked or sold.
  booked,

  /// The ticket for this seat has already been checked in.
  checkedIn,

  /// The seat is unavailable or intentionally blocked.
  blocked;

  String get wireName => switch (this) {
    SeatStatus.checkedIn => 'checked_in',
    _ => name,
  };

  static SeatStatus fromWireName(String value) => switch (value) {
    'available' => SeatStatus.available,
    'held' => SeatStatus.held,
    'booked' => SeatStatus.booked,
    'checked_in' => SeatStatus.checkedIn,
    'blocked' => SeatStatus.blocked,
    _ => throw FormatException('Unknown seat status: $value'),
  };
}
