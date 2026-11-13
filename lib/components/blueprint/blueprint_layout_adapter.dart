import 'package:venue_seat_picker/venue_seat_picker.dart';

import 'blueprint_seat.dart';

import 'package:festapp_core/eshop.dart';

import 'blueprint_layout_contract.dart';
import 'blueprint_model.dart';
import 'blueprint_object_model.dart';

/// Commercial projections are refreshed independently of document/history.
class BlueprintLayoutAdapter {
  BlueprintLayoutAdapter(BlueprintModel source) {
    refresh(source);
  }

  /// Compatibility slots for the form payload; positions never render V2 geometry.
  BlueprintSeat seatSlot(
    BlueprintModel source,
    BlueprintSeatBinding binding,
    int index,
  ) => BlueprintSeat(
    position: SeatPosition(0, index),
    size: 0,
    seatId: binding.spotId,
    label: binding.title,
    seat: BlueprintObjectModel(
      id: binding.spotId,
      title: binding.title,
      spotProduct: binding.productId,
      product: product(binding),
      blueprint: source,
    ),
  )..isSelected = true;

  List<BlueprintSeat> selectedSeats(BlueprintModel source) {
    final bindings =
        source.layoutSnapshot?.seatBindings.values.toList() ??
        const <BlueprintSeatBinding>[];
    return [
      for (var index = 0; index < bindings.length; index++)
        if (state(bindings[index]) == BlueprintSeatState.selectedByMe)
          seatSlot(source, bindings[index], index),
    ];
  }

  VenueLayoutDocument? _document;
  Map<int, ProductModel> products = {};
  Map<String, Map<String, dynamic>> areaAvailability = {};
  Map<int, BlueprintObjectModel> spots = {};
  void refresh(BlueprintModel source) {
    _document = source.layoutSnapshot?.document;
    areaAvailability = Map.from(source.areaAvailability);
    products = {
      for (final p in source.products ?? <ProductModel>[])
        if (p.id != null) p.id!: p,
    };
    spots = {
      for (final s in source.spots ?? <BlueprintObjectModel>[])
        if (s.id != null) s.id!: s,
    };
    for (final spot in spots.values) {
      spot.blueprint = source;
      spot.product = products[spot.spotProduct];
    }
  }

  BlueprintSeatState state(BlueprintSeatBinding binding) => _resolveState(
    spots[binding.spotId]?.stateEnum,
    blocked: binding.blocked,
    hasProduct: binding.productId != null && product(binding) != null,
  );

  /// Shared lifecycle precedence for the main editor and read-only previews.
  static BlueprintSeatState _resolveState(
    BlueprintSeatState? live, {
    required bool blocked,
    required bool hasProduct,
  }) {
    if (const {
      BlueprintSeatState.selected,
      BlueprintSeatState.selectedByMe,
      BlueprintSeatState.ordered,
      BlueprintSeatState.used,
    }.contains(live)) {
      return live!;
    }
    if (blocked || live == BlueprintSeatState.blocked) {
      return BlueprintSeatState.blocked;
    }
    if (!hasProduct) return BlueprintSeatState.empty;
    return live ?? BlueprintSeatState.available;
  }

  /// Minimal server seat facts contain no customer, order, or hold secrets.
  static Map<String, dynamic> readonlySeatPresentation(
    Map<String, dynamic> facts,
  ) {
    if (!BlueprintObjectModel.statesMap.values.contains(facts['state'])) {
      throw const FormatException('Invalid seat lifecycle');
    }
    final live = BlueprintObjectModel.fromJson({'state': facts['state']})
        .stateEnum;
    return _presentationForState(
      _resolveState(
        live,
        blocked: facts['blocked'] == true,
        hasProduct: facts['hasProduct'] == true,
      ),
      label: facts['title']?.toString() ?? '',
      productAvailable: facts['hasProduct'] == true,
    );
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

  /// Customers only need to know that a blocked seat is unavailable.
  Map<String, dynamic> customerPresentation(BlueprintSeatBinding binding) {
    final presentation = publicPresentation(binding);
    if (state(binding) != BlueprintSeatState.blocked) return presentation;
    return {
      ...presentation,
      'fill': blueprintSeatStateFills[BlueprintSeatState.ordered]!,
      'status': 'occupied',
      'state': BlueprintSeatState.ordered.name,
      'selectable': false,
      'selected': false,
    };
  }

  /// Public presentation deliberately excludes all order/customer metadata.
  Map<String, dynamic> publicPresentation(BlueprintSeatBinding binding,
      {VenueLayoutDocument? document}) {
    final resolvedDocument = document ?? _document;
    final node = resolvedDocument?.nodes
        .where((n) => n.id == binding.nodeId)
        .firstOrNull;
    return _presentationForState(
      state(binding),
      label: binding.title,
      productTitle: product(binding)?.title,
      productAvailable: product(binding)?.isAvailable == true,
      authoredFill: node == null
          ? null
          : resolveNodeAppearance(resolvedDocument!, node).values['fill']
              as String?,
    );
  }

  static Map<String, dynamic> _presentationForState(
    BlueprintSeatState state, {
    required String label,
    String? productTitle,
    bool productAvailable = false,
    String? authoredFill,
  }) => {
    'stateMarker': 'auto',
    'label': label,
    // Explicit authored fill also survives optimistic selection in the renderer.
    'fill': state == BlueprintSeatState.selectedByMe ||
            (state == BlueprintSeatState.available && productAvailable)
        ? authoredFill ?? blueprintSeatStateFills[state]!
        : blueprintSeatStateFills[state]!,
    'status': state == BlueprintSeatState.selectedByMe ||
            (state == BlueprintSeatState.available && productAvailable)
        ? 'available'
        : 'occupied',
    'selectable':
        state == BlueprintSeatState.selectedByMe ||
        (state == BlueprintSeatState.available && productAvailable),
    'selected': state == BlueprintSeatState.selectedByMe,
    'state': state.name,
    'productTitle': productTitle,
  };
}
