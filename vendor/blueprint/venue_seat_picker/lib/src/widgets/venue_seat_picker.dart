import 'package:flutter/material.dart';

import '../controller/venue_seat_controller.dart';
import '../model/seat_slot.dart';
import '../model/seat_status.dart';
import 'venue_seat_style.dart';
import 'venue_seat_viewer.dart';

/// One optimistic hold or release request from [VenueSeatPicker].
class SeatSelectionRequest<T, Id extends Object> {
  const SeatSelectionRequest({
    required this.seat,
    required this.seatId,
    required this.selected,
  });

  final T seat;
  final Id seatId;
  final bool selected;
}

typedef SeatSelectionHandler<T, Id extends Object> =
    Future<bool> Function(SeatSelectionRequest<T, Id> request);

/// Optimistic venue seat selection with rollback and duplicate-tap protection.
class VenueSeatPicker<T, Id extends Object> extends StatefulWidget {
  const VenueSeatPicker({
    super.key,
    required this.controller,
    this.onSelectionRequested,
    this.onSelectionChanged,
    this.onSelectionError,
    this.onSelectionLimitReached,
    this.maxSelectedSeats,
    this.isSelectable,
    this.tooltipBuilder,
    this.seatBuilder,
    this.config = const VenueSeatViewConfig(),
  });

  final VenueSeatController<T, Id> controller;
  final SeatSelectionHandler<T, Id>? onSelectionRequested;
  final ValueChanged<Set<Id>>? onSelectionChanged;
  final void Function(Object error, StackTrace stackTrace)? onSelectionError;
  final VoidCallback? onSelectionLimitReached;
  final int? maxSelectedSeats;
  final bool Function(SeatSlot<T, Id> slot)? isSelectable;
  final String Function(BuildContext context, SeatSlot<T, Id> slot)?
  tooltipBuilder;
  final VenueSeatBuilder<T, Id>? seatBuilder;
  final VenueSeatViewConfig config;

  @override
  State<VenueSeatPicker<T, Id>> createState() => _VenueSeatPickerState<T, Id>();
}

class _VenueSeatPickerState<T, Id extends Object>
    extends State<VenueSeatPicker<T, Id>> {
  final Set<Id> _pending = {};

  @override
  Widget build(BuildContext context) => VenueSeatViewer<T, Id>(
    controller: widget.controller,
    onSeatPressed: _toggle,
    tooltipBuilder: widget.tooltipBuilder,
    seatBuilder: widget.seatBuilder,
    config: widget.config,
  );

  Future<void> _toggle(SeatSlot<T, Id> slot) async {
    final controller = widget.controller;
    final seat = slot.seat;
    final seatId = slot.seatId;
    if (seat == null || seatId == null || _pending.contains(seatId)) return;
    if (widget.isSelectable?.call(slot) == false) return;
    final select = !slot.isSelected;
    if (select && slot.status != SeatStatus.available) return;
    if (select &&
        widget.maxSelectedSeats != null &&
        controller.selectedSeatIds.length >= widget.maxSelectedSeats!) {
      widget.onSelectionLimitReached?.call();
      return;
    }

    _pending.add(seatId);
    controller.setSelection(slot, select, pending: true);
    widget.onSelectionChanged?.call(controller.selectedSeatIds);

    var accepted = false;
    try {
      accepted =
          await (widget.onSelectionRequested?.call(
                SeatSelectionRequest<T, Id>(
                  seat: seat,
                  seatId: seatId,
                  selected: select,
                ),
              ) ??
              Future.value(true));
    } catch (error, stackTrace) {
      widget.onSelectionError?.call(error, stackTrace);
    }
    _pending.remove(seatId);
    if (!controller.isDisposed) {
      if (!accepted) controller.setSelection(slot, !select);
      controller.setPending(slot, false);
      if (!accepted && mounted) {
        widget.onSelectionChanged?.call(controller.selectedSeatIds);
      }
    }
  }
}
