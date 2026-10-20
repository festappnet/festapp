import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'blueprint_seat.dart';
import 'package:festapp_core/eshop.dart';
import 'blueprint_layout_contract.dart';
import 'blueprint_model.dart';
import 'blueprint_object_model.dart';
import 'blueprint_seat_state.dart';

/// Commercial projections are refreshed independently of document/history.
class BlueprintLayoutAdapter {
  BlueprintLayoutAdapter(BlueprintModel source) {
    refresh(source);
  }

  /// Compatibility slots for the form payload; positions never render V2 geometry.
  BlueprintSeat seatSlot(
          BlueprintModel source, BlueprintSeatBinding binding, int index) =>
      BlueprintSeat(
          position: SeatPosition(0, index),
          size: 0,
          seatId: binding.spotId,
          label: binding.title,
          seat: BlueprintObjectModel(
              id: binding.spotId,
              title: binding.title,
              spotProduct: binding.productId,
              product: product(binding),
              blueprint: source))
        ..isSelected = true;

  List<BlueprintSeat> selectedSeats(BlueprintModel source) {
    final bindings = source.layoutSnapshot?.seatBindings.values.toList() ??
        const <BlueprintSeatBinding>[];
    return [
      for (var index = 0; index < bindings.length; index++)
        if (state(bindings[index]) == BlueprintSeatState.selectedByMe)
          seatSlot(source, bindings[index], index)
    ];
  }

  Map<int, ProductModel> products = {};
  Map<String, Map<String, dynamic>> areaAvailability = {};
  Map<int, BlueprintObjectModel> spots = {};
  void refresh(BlueprintModel source) {
    areaAvailability = Map.from(source.areaAvailability);
    products = {
      for (final p in source.products ?? <ProductModel>[])
        if (p.id != null) p.id!: p
    };
    spots = {
      for (final s in source.spots ?? <BlueprintObjectModel>[])
        if (s.id != null) s.id!: s
    };
    for (final spot in spots.values) {
      spot.blueprint = source;
      spot.product = products[spot.spotProduct];
    }
  }

  BlueprintSeatState state(BlueprintSeatBinding binding) {
    final live = spots[binding.spotId]?.stateEnum;
    if (const {
      BlueprintSeatState.selected,
      BlueprintSeatState.selectedByMe,
      BlueprintSeatState.ordered,
      BlueprintSeatState.used
    }.contains(live)) {
      return live!;
    }
    if (binding.blocked || live == BlueprintSeatState.blocked) {
      return BlueprintSeatState.blocked;
    }
    if (binding.productId == null || product(binding) == null) {
      return BlueprintSeatState.empty;
    }
    return live ?? BlueprintSeatState.available;
  }

  bool protected(BlueprintSeatBinding binding) => const {
        BlueprintSeatState.selected,
        BlueprintSeatState.selectedByMe,
        BlueprintSeatState.ordered,
        BlueprintSeatState.used,
      }.contains(state(binding));
  ProductModel? product(BlueprintSeatBinding binding) =>
      products[binding.productId];
  Set<String> protectedIds(BlueprintLayoutSnapshot snapshot) => {
        for (final binding in snapshot.seatBindings.values)
          if (protected(binding)) binding.nodeId,
      };

  /// Public presentation deliberately excludes all order/customer metadata.
  Map<String, dynamic> publicPresentation(BlueprintSeatBinding binding) => {
        'stateMarker':
            state(binding) == BlueprintSeatState.used ? 'none' : 'auto',
        'label': binding.title,
        'fill': switch (state(binding)) {
          BlueprintSeatState.available ||
          BlueprintSeatState.selectedByMe =>
            '#267329FF',
          BlueprintSeatState.selected => '#00000042',
          BlueprintSeatState.ordered => '#0000001F',
          BlueprintSeatState.used => '#412673FF',
          BlueprintSeatState.blocked => '#000000DE',
          BlueprintSeatState.empty => '#267329FF',
        },
        'status': switch (state(binding)) {
          BlueprintSeatState.ordered || BlueprintSeatState.used => 'occupied',
          BlueprintSeatState.selected => 'reserved',
          BlueprintSeatState.selectedByMe => 'available',
          BlueprintSeatState.blocked => 'blocked',
          BlueprintSeatState.empty => 'unavailable',
          _ => 'available',
        },
        'selectable': state(binding) == BlueprintSeatState.selectedByMe ||
            (state(binding) == BlueprintSeatState.available &&
                product(binding)?.isAvailable == true),
        'selected': state(binding) == BlueprintSeatState.selectedByMe,
        'state': state(binding).name,
        'productTitle': product(binding)?.title,
      };
}
