import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/blueprint/blueprint_seat.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/widgets/buttons_helper.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

/// Festapp reservation adapter around the package's optimistic
/// [VenueSeatPicker].
/// SQL remains authoritative; a rejected RPC automatically restores the UI.
class SeatReservationWidget extends StatefulWidget {
  static const int boxSize = 15;

  final int blueprintId;
  final String secret;
  final String formDataKey;
  final void Function(List<BlueprintSeat>)? onSelectionChanged;
  final void Function(List<BlueprintSeat>?)? onCloseSeatReservation;
  final List<BlueprintSeat> selectedSeats;
  final int? maxTickets;

  const SeatReservationWidget({
    super.key,
    required this.blueprintId,
    required this.secret,
    required this.formDataKey,
    required this.selectedSeats,
    this.maxTickets,
    this.onSelectionChanged,
    this.onCloseSeatReservation,
  });

  @override
  State<SeatReservationWidget> createState() => _SeatReservationWidgetState();
}

class _SeatReservationWidgetState extends State<SeatReservationWidget> {
  BlueprintModel? blueprint;
  late final VenueSeatController<BlueprintObjectModel, Object> _controller;
  late List<BlueprintSeat> _selectedSeats;

  @override
  void initState() {
    super.initState();
    _selectedSeats = List.of(widget.selectedSeats);
    _controller = VenueSeatController<BlueprintObjectModel, Object>(
      adapter: blueprintSeatAdapter,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: Container(
            constraints:
                const BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
            child: Column(
              children: [
                Flexible(
                  child: blueprint == null
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
                          child: TooltipTheme(
                              data: TooltipThemeData(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .inverseSurface
                                      .withValues(alpha: .95),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onInverseSurface,
                                    ),
                              ),
                              child:
                                  VenueSeatPicker<BlueprintObjectModel, Object>(
                                controller: _controller,
                                maxSelectedSeats: widget.maxTickets,
                                onSelectionLimitReached: () => ToastHelper.Show(
                                  context,
                                  BlueprintStrings.toastMaxTicketsReached,
                                ),
                                onSelectionRequested: _requestSelection,
                                onSelectionChanged: _selectionChanged,
                                tooltipBuilder: (context, slot) =>
                                    slot.seat?.blueprintTooltip(context) ?? '',
                              )),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ButtonsHelper.primaryButton(
                    context: context,
                    onPressed: () =>
                        widget.onCloseSeatReservation?.call(_selectedSeats),
                    label: CommonStrings.continueAction,
                    width: 250,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Future<bool> _requestSelection(
    SeatSelectionRequest<BlueprintObjectModel, Object> request,
  ) async {
    final accepted = await ExceptionHandler.guard<bool>(
      context,
      futureFunction: () => DbOrders.selectSpot(
        context,
        widget.formDataKey,
        widget.secret,
        request.seat.id!,
        request.selected,
      ),
    );
    return accepted ?? false;
  }

  void _selectionChanged(Set<Object> selectedIds) {
    _selectedSeats = selectedIds
        .map(_controller.slotForId)
        .whereType<BlueprintSeat>()
        .toList();
    widget.onSelectionChanged?.call(_selectedSeats);
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    final loaded = await DbForms.getBlueprint(
      widget.secret,
      widget.formDataKey,
      widget.blueprintId,
    );
    if (loaded == null || !mounted) return;
    blueprint = loaded;

    final selectedIds = _selectedSeats.map((seat) => seat.seatId).nonNulls;

    _controller.loadPlan(
      rows: loaded.configuration?.height ?? 1,
      columns: loaded.configuration?.width ?? 1,
      seats: (loaded.objects ?? const [])
          .where((object) => object.x != null && object.y != null),
      seatSize: SeatReservationWidget.boxSize.toDouble(),
      backdrop: switch (loaded.backgroundSvg) {
        final String source when source.isNotEmpty =>
          VenueBackdrop.parse(source),
        _ => null,
      },
      initiallySelected: selectedIds,
    );
    _selectedSeats =
        _controller.slots.where((slot) => slot.isSelected).toList();
    setState(() {});
  }
}
