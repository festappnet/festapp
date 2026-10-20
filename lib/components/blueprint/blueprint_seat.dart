import 'package:venue_seat_picker/venue_seat_picker.dart';

import 'blueprint_object_model.dart';
import 'blueprint_seat_state.dart';

export 'blueprint_seat_state.dart';

/// Festapp's domain-specific seat slot at the public package seam.
typedef BlueprintSeat = SeatSlot<BlueprintObjectModel, Object>;

final blueprintSeatAdapter = SeatAdapter<BlueprintObjectModel, Object>(
  idOf: (seat) => seat.id ?? seat,
  positionOf: (seat) => SeatPosition(
    seat.y ??
        (throw StateError('Blueprint seat is missing its row coordinate')),
    seat.x ??
        (throw StateError('Blueprint seat is missing its column coordinate')),
  ),
  statusOf: (seat) => switch (seat.stateEnum ?? BlueprintSeatState.empty) {
    BlueprintSeatState.selected => SeatStatus.held,
    BlueprintSeatState.ordered => SeatStatus.booked,
    BlueprintSeatState.used => SeatStatus.checkedIn,
    BlueprintSeatState.blocked => SeatStatus.blocked,
    BlueprintSeatState.empty ||
    BlueprintSeatState.available ||
    BlueprintSeatState.selectedByMe =>
      SeatStatus.available,
  },
  labelOf: (seat) => seat.title,
  groupOf: (seat) => seat.group?.id ?? seat.groupId,
);
