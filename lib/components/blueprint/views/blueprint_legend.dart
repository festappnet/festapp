import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/blueprint_strings.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

import '../blueprint_seat_state.dart';
import '../seat_reservation/widgets/seat_reservation_widget.dart';
import 'blueprint_editor_tab.dart';

class BlueprintLegend extends StatelessWidget {
  final BlueprintSelectionMode currentSelectionMode;
  final ValueChanged<BlueprintSelectionMode> onModeSelected;

  // New properties for the Confirm Button
  final int selectedCount;
  final VoidCallback? onConfirmOrder;
  final Map<BlueprintSeatState, int> stateCounts;
  final bool allowOrderActions;

  const BlueprintLegend({
    super.key,
    required this.currentSelectionMode,
    required this.onModeSelected,
    this.selectedCount = 0,
    this.onConfirmOrder,
    this.stateCounts = const {},
    this.allowOrderActions = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Text(
            _getHelpText(),
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.left,
          ),
        ),
        _buildLegend(context),
      ],
    );
  }

  String _getHelpText() {
    if (currentSelectionMode == BlueprintSelectionMode.swapSeats) {
      return BlueprintStrings.swapHelpIntro;
    } else if (currentSelectionMode == BlueprintSelectionMode.createNewOrder) {
      return BlueprintStrings.createOrderHelp;
    }
    return BlueprintStrings.legendInstruction;
  }

  Widget _buildLegend(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- Drawing Tools ---
        _buildLegendItem(
          context: context,
          label: BlueprintStrings.legendBlackArea,
          state: BlueprintSeatState.blocked,
          isActive: currentSelectionMode == BlueprintSelectionMode.addBlack,
          onTap: () => onModeSelected(BlueprintSelectionMode.addBlack),
        ),
        const SizedBox(height: 8),
        _buildLegendItem(
          context: context,
          label: BlueprintStrings.legendAvailable,
          state: BlueprintSeatState.available,
          isActive: currentSelectionMode == BlueprintSelectionMode.addAvailable,
          onTap: () => onModeSelected(BlueprintSelectionMode.addAvailable),
          count: stateCounts[BlueprintSeatState.available],
        ),
        const SizedBox(height: 8),
        _buildLegendItem(
          context: context,
          label: BlueprintStrings.legendEmpty,
          state: BlueprintSeatState.empty,
          isActive: currentSelectionMode == BlueprintSelectionMode.emptyArea,
          onTap: () => onModeSelected(BlueprintSelectionMode.emptyArea),
          drawBorder: true,
        ),

        if (allowOrderActions) const SizedBox(height: 16),

        // --- Action Tools ---
        if (allowOrderActions) _buildLegendItem(
          context: context,
          label: BlueprintStrings.legendSwapSeats,
          state: BlueprintSeatState.empty,
          isActive: currentSelectionMode == BlueprintSelectionMode.swapSeats,
          forceHighlight:
              true, // Keeps orange border for Swap to indicate "special/warning"
          onTap: () => onModeSelected(BlueprintSelectionMode.swapSeats),
        ),
        if (allowOrderActions) const SizedBox(height: 8),

        // --- Create Order with Button ---
        if (allowOrderActions) Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLegendItem(
              context: context,
              label: BlueprintStrings.legendCreateOrder,
              state: BlueprintSeatState.selectedByMe,
              isActive:
                  currentSelectionMode == BlueprintSelectionMode.createNewOrder,
              forceHighlight: false, // REMOVED orange border here
              onTap: () =>
                  onModeSelected(BlueprintSelectionMode.createNewOrder),
            ),

            // The Button appears here if mode is active
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: currentSelectionMode ==
                      BlueprintSelectionMode.createNewOrder
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: selectedCount > 0 ? onConfirmOrder : null,
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: Colors.black26,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon:
                              const Icon(Icons.check_circle_outline, size: 20),
                          label: Text(
                            "${BlueprintStrings.btnCreateOrder} ($selectedCount)",
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),

        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),

        // --- Static Legend Items ---
        _buildLegendItem(
          context: context,
          label: BlueprintStrings.legendUsed,
          state: BlueprintSeatState.used,
          isActive: false,
          grayedOut: true,
          count: stateCounts[BlueprintSeatState.used],
        ),
        const SizedBox(height: 8),
        _buildLegendItem(
          context: context,
          label: BlueprintStrings.legendOccupied,
          state: BlueprintSeatState.ordered,
          isActive: false,
          grayedOut: true,
          count: stateCounts[BlueprintSeatState.ordered],
        )
      ],
    );
  }

  Widget _buildLegendItem({
    required BuildContext context,
    required String label,
    required BlueprintSeatState state,
    bool isActive = false,
    VoidCallback? onTap,
    bool grayedOut = false,
    bool forceHighlight = false,
    int? count,
    bool drawBorder = false,
  }) {
    return MouseRegion(
      cursor:
          grayedOut ? SystemMouseCursors.forbidden : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: grayedOut ? null : onTap,
        child: Opacity(
          opacity: 1.0,
          child: Container(
            decoration: BoxDecoration(
              color: isActive
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
                  : null,
              border: Border.all(
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: drawBorder
                      ? BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        )
                      : null,
                  child: VenueSeatMarker(
                    status: switch (state) {
                      BlueprintSeatState.empty => null,
                      BlueprintSeatState.available ||
                      BlueprintSeatState.selectedByMe =>
                        SeatStatus.available,
                      BlueprintSeatState.selected => SeatStatus.held,
                      BlueprintSeatState.ordered => SeatStatus.booked,
                      BlueprintSeatState.used => SeatStatus.checkedIn,
                      BlueprintSeatState.blocked => SeatStatus.blocked,
                    },
                    selected: state == BlueprintSeatState.selectedByMe,
                    isSwapHighlighted: forceHighlight,
                    size: SeatReservationWidget.boxSize.toDouble() *
                        (drawBorder ? 0.7 : 1.0),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  count != null ? "$label ($count)" : label,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
