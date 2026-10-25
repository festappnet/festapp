import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/models/spot_management_constants.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/inventory/db_spots.dart';
import 'package:trina_grid/trina_grid.dart';

import 'spot_management_models_and_constants.dart';

class SpotMatrixRow extends ITrinaRowModel {
  // A single, unified object containing all the row's metadata.
  final SpotManagementRowReference rowReference;

  /// A unique identifier for the row, e.g., 'resource_12_slot_34' or 'resource_12_index_1'.
  String get rowIdentifier => rowReference.slot != null
      ? 'resource_${rowReference.resource.id}_slot_${rowReference.slot!.id}'
      : 'resource_${rowReference.resource.id}_index_${rowReference.implicitSlotIndex}';

  // The grid needs a stable ID. We use our generated unique identifier.
  @override
  String get id => rowIdentifier;

  SpotMatrixRow({
    required this.rowReference,
  });

  /// Converts this model into a TrinaRow for the data grid.
  @override
  TrinaRow toTrinaRow(BuildContext context) {
    final cells = <String, TrinaCell>{};

    // --- Visible and Identifier Columns ---
    cells[SpotManagementConstants.rowIdentifier] =
        TrinaCell(value: rowIdentifier);

    String displayTitle = rowReference.resource.title ??
        InventoryStrings.resourceDefaultTitle(
            rowReference.resource.id.toString());
    if (rowReference.slot?.title != null) {
      displayTitle = rowReference.slot!.title!;
    } else if (rowReference.implicitSlotIndex != null) {
      displayTitle = "$displayTitle #${rowReference.implicitSlotIndex}";
    }
    cells[SpotManagementConstants.resourceTitle] =
        TrinaCell(value: displayTitle);

    // --- The SINGLE Hidden Reference Column ---
    // Pass the entire reference object. This object will be updated in memory and persisted back to the grid state.
    cells[SpotManagementConstants.rowReference] =
        TrinaCell(value: rowReference);

    // --- Dynamic Context Columns ---
    // Populate cells for each context based on the CURRENT state from the reference object.
    rowReference.currentSpotsInRow.forEach((contextId, spot) {
      final fieldName =
          '${SpotManagementConstants.contextColumnPrefix}$contextId';
      // The cell value is now ONLY the display string, with no ID.
      final cellValue = spot?.order?.toCustomerData() ?? '';
      cells[fieldName] = TrinaCell(value: cellValue);
    });

    return TrinaRow(cells: cells);
  }

  /// Reconstructs the model from grid data.
  static SpotMatrixRow fromPlutoJson(Map<String, dynamic> json) {
    // Reconstruct the object by simply extracting our unified reference object.
    // This object will contain the latest state as updated by the cell renderers.
    final rowRef = json[SpotManagementConstants.rowReference]
        as SpotManagementRowReference;
    return SpotMatrixRow(rowReference: rowRef);
  }

  /// Called by the grid to save changes.
  @override
  Future<void> updateMethod(BuildContext context) async {
    final List<Map<String, dynamic>> changes = [];
    final initialAssignments = rowReference.initialSpotsInRow;
    final currentAssignments = rowReference.currentSpotsInRow;

    // Compare the initial state with the current state to detect changes.
    for (final contextId in initialAssignments.keys) {
      final oldSpot = initialAssignments[contextId];
      final newSpot = currentAssignments[contextId];

      // If the assignment hasn't actually changed, skip it.
      if (oldSpot?.id == newSpot?.id) continue;

      changes.add({
        'old_spot_id': oldSpot?.id,
        'new_spot_id': newSpot?.id,
        'resource_id': rowReference.resource.id,
        'resource_slot_id': rowReference.slot?.id,
        'inventory_context_id': contextId,
      });
    }

    if (changes.isNotEmpty) {
      // Make a single efficient batch call to the database service.
      await DbSpots.updateSpotAssignments(changes);
    }
  }

  @override
  String toBasicString() =>
      rowReference.resource.title ??
      InventoryStrings.resourceDefaultTitle(
          rowReference.resource.id.toString());

  @override
  Future<void> deleteMethod(BuildContext context) async {
    // Deleting a resource row is not a supported operation in this view.
  }
}
