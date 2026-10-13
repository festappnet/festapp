import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/models/spot_management_models_and_constants.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:trina_grid/trina_grid.dart';

import '../models/spot_management_constants.dart';
import 'inventory_strings.dart';
import 'spot_management_columns.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

/// A stateful dialog that allows searching and selecting a spot for a single cell.
class SpotSearchDialog extends StatefulWidget {
  final TrinaColumnRendererContext rendererContext;
  final SpotManagementRowReference rowReference;
  final SpotModel? currentSpot;
  final int contextId;
  final ValueNotifier<String> searchNotifier;

  const SpotSearchDialog({
    super.key,
    required this.rendererContext,
    required this.rowReference,
    required this.currentSpot,
    required this.contextId,
    required this.searchNotifier,
  });

  @override
  State<SpotSearchDialog> createState() => _SpotSearchDialogState();
}

class _SpotSearchDialogState extends State<SpotSearchDialog> {
  final _searchController = TextEditingController();
  List<SpotModel> _availableSpots = [];
  List<SpotModel> _filteredSpots = [];

  @override
  void initState() {
    super.initState();
    _prepareInitialSpotList();
    _searchController.text = widget.searchNotifier.value;
    _searchController.addListener(_onSearchChanged);
    _filterSpots();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    widget.searchNotifier.value = _searchController.text;
    _filterSpots();
  }

  void _prepareInitialSpotList() {
    // --- AVAILABILITY LOGIC ---
    // Find all spots already assigned in the current context column by inspecting the reference objects of all rows.
    final assignedSpotIdsInContext = <int>{};
    for (final row in widget.rendererContext.stateManager.rows) {
      final rowRef = row.cells[SpotManagementConstants.rowReference]?.value
          as SpotManagementRowReference?;
      final spotInCell = rowRef?.currentSpotsInRow[widget.contextId];
      if (spotInCell != null) {
        assignedSpotIdsInContext.add(spotInCell.id!);
      }
    }

    final availableSpotsForDialog = <SpotModel>[];
    for (var spot in widget.rowReference.allSpotsMap.values) {
      if (spot.inventoryContextId == widget.contextId && spot.order != null) {
        // A spot is available if it's not assigned elsewhere in this column, OR if it's the one currently in this cell.
        if (!assignedSpotIdsInContext.contains(spot.id) ||
            spot.id == widget.currentSpot?.id) {
          availableSpotsForDialog.add(spot);
        }
      }
    }

    // --- SORTING LOGIC ---
    final currentResourceId = widget.rowReference.resource.id;
    final assignedSpotIdsToThisResource = <int>{};

    for (final row in widget.rendererContext.stateManager.rows) {
      final rowRef = row.cells[SpotManagementConstants.rowReference]?.value
          as SpotManagementRowReference?;
      if (rowRef?.resource.id == currentResourceId) {
        for (final spot in rowRef!.currentSpotsInRow.values) {
          if (spot != null) {
            assignedSpotIdsToThisResource.add(spot.id!);
          }
        }
      }
    }

    availableSpotsForDialog.sort((a, b) {
      final isAOnThisResource = assignedSpotIdsToThisResource.contains(a.id);
      final isBOnThisResource = assignedSpotIdsToThisResource.contains(b.id);
      if (isAOnThisResource && !isBOnThisResource) return -1;
      if (!isAOnThisResource && isBOnThisResource) return 1;
      return (a.order!.toCustomerData()).compareTo(b.order!.toCustomerData());
    });

    setState(() {
      _availableSpots = availableSpotsForDialog;
      _filteredSpots = availableSpotsForDialog;
    });
  }

  void _filterSpots() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredSpots = List.from(_availableSpots);
      });
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      setState(() {
        _filteredSpots = _availableSpots.where((spot) {
          final customerData = spot.order!.toCustomerData();
          final normalizedName =
              Utilities.removeDiacritics(customerData.toLowerCase());
          return normalizedName.contains(normalizedQuery);
        }).toList();
      });
    }
  }

  /// Pops the dialog and returns the selected spot, or an action object.
  void _selectAndPop(Object? result) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(InventoryStrings.searchDialogTitle(
          widget.rendererContext.column.title)),
      contentPadding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 0),
      content: SizedBox(
        width: 350,
        height: 500,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: InventoryStrings.searchDialogHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.0)),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                children: [
                  // Option to unassign the spot
                  ListTile(
                    title: Text(InventoryStrings.searchDialogUnassign),
                    onTap: () => _selectAndPop(
                        UnassignSpotAction()), // Pop the sentinel object
                  ),
                  const Divider(height: 1),
                  // List of available spots
                  ..._filteredSpots.map((spot) {
                    final spotTitle = spot.order!.toCustomerData();
                    return ListTile(
                      title: Text(spotTitle),
                      onTap: () {
                        _selectAndPop(spot); // Pop the spot object
                      },
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        // Action: Storno (Cancel)
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Pops with null
          child: Text(CommonStrings.storno),
        ),
      ],
    );
  }
}
