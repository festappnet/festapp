import 'package:fstapp/components/blueprint/blueprint_layout_adapter.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';

/// Rebuild a reviewed quote from current held seats and current product prices.
/// Released seats leave the attendee's answers available for reselection.
Map<int, BlueprintSeat> refreshedReservedPaymentSeats(
    BlueprintModel blueprint, Iterable<int> previousSeatIds) {
  final previous = previousSeatIds.toSet();
  final result = <int, BlueprintSeat>{};
  for (final seat in BlueprintLayoutAdapter(blueprint).selectedSeats(blueprint)) {
    final id = seat.seatId;
    if (id is int && previous.contains(id) && seat.seat?.product?.price != null) {
      result[id] = seat;
    }
  }
  return result;
}
