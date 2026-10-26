import 'package:venue_seat_picker/venue_seat_picker.dart';

import 'blueprint_object_model.dart';

export 'blueprint_seat_state.dart';

/// Festapp's domain-specific seat slot at the public package seam.
typedef BlueprintSeat = SeatSlot<BlueprintObjectModel, Object>;
