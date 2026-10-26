import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/spot_management_models_and_constants.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';
import 'package:trina_grid/trina_grid.dart';

import '../models/spot_management_constants.dart';
import 'inventory_strings.dart';
import 'spot_search_dialog.dart';

class UnassignSpotAction {}

class SpotManagementColumns {
  static List<TrinaColumn> generateColumns(
    BuildContext context,
    List<InventoryContextModel> inventoryContexts,
    ValueNotifier<String> dialogSearchNotifier,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget cellRenderer(TrinaColumnRendererContext rendererContext) {
      final rowRef = rendererContext
          .row
          .cells[SpotManagementConstants.rowReference]
          ?.value as SpotManagementRowReference?;
      if (rowRef == null) return const SizedBox.shrink();

      // The cell value is now purely for display.
      final displayValue = rendererContext.cell.value as String?;

      final colorList = isDark
          ? SpotManagementConstants.darkModeResourceColors
          : SpotManagementConstants.lightModeResourceColors;
      final resourceColor =
          colorList[rowRef.resource.id!.hashCode % colorList.length];

      Widget cellContent;
      if (displayValue != null && displayValue.isNotEmpty) {
        cellContent = Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: resourceColor,
              borderRadius: BorderRadius.circular(16.0),
            ),
            child: Text(
              displayValue,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: SpotManagementConstants.getTextColorForBackground(
                    resourceColor),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      } else {
        cellContent = Center(
          child: TextButton.icon(
            onPressed: null,
            icon: Icon(Icons.add, size: 16, color: Colors.grey.shade600),
            label: Text(
              InventoryStrings.spotManagementAssign,
              style: TextStyle(
                  color: Colors.grey.shade600, fontWeight: FontWeight.normal),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        );
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final contextId = int.parse(rendererContext.column.field
              .replaceAll(SpotManagementConstants.contextColumnPrefix, ''));
          _showSpotSelectionDialog(
            context,
            rendererContext,
            rowRef,
            contextId,
            dialogSearchNotifier,
          );
        },
        child: Container(
          width: double.infinity,
          height: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          child: cellContent,
        ),
      );
    }

    List<TrinaColumn> columns = [
      TrinaColumn(
        field: SpotManagementConstants.resourceTitle,
        title: InventoryStrings.spotManagementResource,
        type: TrinaColumnType.text(),
        readOnly: true,
        enableEditingMode: false,
        width: 250,
        renderer: (rendererContext) {
          final rowRef = rendererContext
              .row
              .cells[SpotManagementConstants.rowReference]
              ?.value as SpotManagementRowReference?;
          if (rowRef == null) return const SizedBox.shrink();

          final colorList = isDark
              ? SpotManagementConstants.darkModeResourceColors
              : SpotManagementConstants.lightModeResourceColors;
          final resourceColor =
              colorList[rowRef.resource.id!.hashCode % colorList.length];

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                      color: resourceColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    rendererContext.cell.value.toString(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      // --- All hidden data is now in this single reference object ---
      TrinaColumn(
          field: SpotManagementConstants.rowReference,
          hide: true,
          type: TrinaColumnType.text(),
          title: ''),
    ];

    inventoryContexts.sort((a, b) =>
        (a.blockDate ?? DateTime(0)).compareTo(b.blockDate ?? DateTime(0)));

    for (var contextModel in inventoryContexts) {
      final fieldName =
          "${SpotManagementConstants.contextColumnPrefix}${contextModel.id}";
      columns.add(
        TrinaColumn(
          field: fieldName,
          title: contextModel
              .getContextTitle(context), // Assuming this helper exists
          type: TrinaColumnType.text(),
          readOnly: true,
          enableEditingMode: false,
          width: 200,
          textAlign: TrinaColumnTextAlign.center,
          renderer: cellRenderer,
        ),
      );
    }

    return columns;
  }

  static Future<void> _showSpotSelectionDialog(
    BuildContext context,
    TrinaColumnRendererContext rendererContext,
    SpotManagementRowReference rowReference, // Pass the unified object
    int contextId,
    ValueNotifier<String> dialogSearchNotifier,
  ) async {
    final currentSpot = rowReference.currentSpotsInRow[contextId];

    // The dialog now returns a generic Object? to accommodate different return types.
    final result = await showDialog<Object?>(
      context: context,
      builder: (BuildContext dialogContext) {
        return SpotSearchDialog(
          rendererContext: rendererContext,
          rowReference: rowReference,
          currentSpot: currentSpot,
          contextId: contextId,
          searchNotifier: dialogSearchNotifier,
        );
      },
    );

    // If the result is null, it means the dialog was dismissed (e.g., by tapping outside or pressing 'Storno').
    // In this case, we do nothing.
    if (result == null) {
      return;
    }

    // If we have a result, we determine what it was and update the state.
    SpotModel? selectedSpot;
    if (result is UnassignSpotAction) {
      // The user explicitly tapped "Unassign".
      selectedSpot = null;
    } else if (result is SpotModel) {
      // The user selected a specific spot.
      selectedSpot = result;
    }

    // Modify the reference object in memory with the new selection.
    rowReference.currentSpotsInRow[contextId] = selectedSpot;

    // Get the cells that need to be updated.
    final visibleCell = rendererContext.cell;

    // Trigger updates in the grid's state manager.
    final stateManager = rendererContext.stateManager;

    // Update the visible cell with the new display text.
    stateManager.changeCellValue(
        visibleCell, selectedSpot?.order?.toCustomerData() ?? '',
        force: true, notify: true);
  }
}
