import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/inventory/models/spot_management_bundle.dart';
import 'package:fstapp/components/inventory/models/spot_management_models_and_constants.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';
import 'package:fstapp/components/inventory/db_spots.dart';
import 'package:fstapp/components/inventory/views/spot_management_columns.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/utilities_all.dart';

import '../models/spot_management_constants.dart';
import '../models/spot_matrix_row_model.dart';
import 'inventory_strings.dart';

class SpotManagementView extends StatefulWidget {
  final int inventoryPoolId;
  const SpotManagementView({super.key, required this.inventoryPoolId});

  @override
  SpotManagementViewState createState() => SpotManagementViewState();
}

class _SpotIdentifier {
  final int id;
  _SpotIdentifier(this.id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SpotIdentifier &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class SpotManagementViewState extends State<SpotManagementView> {
  SingleDataGridController<SpotMatrixRow>? _controller;
  bool _isLoading = true;
  final _dialogSearchNotifier = ValueNotifier<String>('');

  // New: A temporary cache for the initial data bundle to avoid a double fetch.
  SpotManagementBundle? _initialBundle;

  static final String _clearAllTitle =
      InventoryStrings.spotManagementClearAllTitle;
  static final String _clearAllConfirmation =
      InventoryStrings.spotManagementClearAllConfirmation;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(covariant SpotManagementView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.inventoryPoolId != widget.inventoryPoolId) {
      _initializeController();
    }
  }

  @override
  void dispose() {
    _dialogSearchNotifier.dispose();
    // It's good practice to also dispose the controller if it's not null.
    // Assuming SingleDataGridController has a dispose method.
    // _controller?.dispose();
    super.dispose();
  }

  /// New: This function handles fetching data for the data grid.
  /// It uses the cached `_initialBundle` for the first load and
  /// fetches fresh data for subsequent refreshes.
  Future<List<SpotMatrixRow>> fetchGridData() async {
    // If we have a pre-fetched bundle, use it and clear the cache.
    if (_initialBundle != null) {
      final bundle = _initialBundle!;
      _initialBundle = null; // Consume the cached bundle
      return _generateMatrixRows(bundle);
    }

    // If no cached bundle, fetch fresh data from the database.
    // This path is taken on user-initiated refreshes within the grid.
    final bundle =
        await DbSpots.getSpotManagementBundle(widget.inventoryPoolId);
    return _generateMatrixRows(bundle);
  }

  /// Fetches initial data once and configures the data grid controller.
  /// The controller itself will then use the cached data for its first render.
  Future<void> _initializeController() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch #1: This is now the ONLY initial fetch.
      _initialBundle =
          await DbSpots.getSpotManagementBundle(widget.inventoryPoolId);

      if (mounted) {
        setState(() {
          _controller = SingleDataGridController<SpotMatrixRow>(
            context: context,
            // The controller will call this function to get its data.
            // On the first run, it will get the cached `_initialBundle`.
            loadData: fetchGridData,
            fromPlutoJson: SpotMatrixRow.fromPlutoJson,
            idColumn: SpotManagementConstants.rowIdentifier,
            firstColumnType: DataGridFirstColumn.none,
            // Use the cached bundle for generating initial columns to avoid null errors.
            columns: SpotManagementColumns.generateColumns(
              context,
              _initialBundle!.inventoryContexts,
              _dialogSearchNotifier,
            ),
            actionsExtended: DataGridActionsController(
              isAddActionPossible: () => false,
            ),
            headerChildren: [
              DataGridAction(
                name: _clearAllTitle,
                action: (controller, [_]) => _clearAllAssignments(controller),
                isEnabled: () => true,
              ),
            ],
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.error("Error loading spot management data: $e");
      if (mounted) {
        // Clear the cached bundle on error to prevent using stale/bad data.
        _initialBundle = null;
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // UPDATED: Now groups by the more reliable order.id
  Map<Object, List<SpotModel>> _groupSpotsByCustomer(List<SpotModel> spots) {
    final map = <Object, List<SpotModel>>{};
    for (final spot in spots) {
      final Object customerId = spot.order?.id ?? _SpotIdentifier(spot.id!);
      map.putIfAbsent(customerId, () => []).add(spot);
    }
    return map;
  }

  Map<int, List<SpotModel>> _groupSpotsByContext(List<SpotModel> spots) {
    final map = <int, List<SpotModel>>{};
    for (final spot in spots) {
      if (spot.inventoryContextId != null) {
        map.putIfAbsent(spot.inventoryContextId!, () => []).add(spot);
      }
    }
    return map;
  }

  /// Generates the list of [SpotMatrixRow] models for the data grid using a
  /// single, unified "best fit" algorithm.
  List<SpotMatrixRow> _generateMatrixRows(SpotManagementBundle bundle) {
    final allSpotsMap = {for (var spot in bundle.spots) spot.id!: spot};
    bundle.resources
        .sort((a, b) => Utilities.naturalCompare(a.title ?? '', b.title ?? ''));

    final List<SpotMatrixRow> generatedRows = [];
    final int numContexts = bundle.inventoryContexts.length;

    for (final ResourceModel resource in bundle.resources) {
      // 1. SETUP (Unchanged)
      final availableSpots =
          bundle.spots.where((s) => s.resourceId == resource.id).toList();
      final slotsForResource = bundle.resourceSlots
          .where((s) => s.resourceId == resource.id)
          .toList();
      final int rowCount = slotsForResource.isNotEmpty
          ? slotsForResource.length
          : ((resource.capacity ?? 1) > 0 ? resource.capacity! : 1);
      final List<SpotMatrixRow> rowsForThisResource = [];

      // 2. BUILD ALL ROWS WITH SPOTS (Now using typed IDs)
      for (int level = numContexts; level >= 1; level--) {
        if (rowsForThisResource.length >= rowCount) break;

        bool wasRowBuiltInPass;
        do {
          wasRowBuiltInPass = false;
          if (rowsForThisResource.length >= rowCount || availableSpots.isEmpty)
            break;

          final spotsByCustomer = _groupSpotsByCustomer(availableSpots);
          Object? candidateCustomer; // Key is now Object?

          for (final customerId in spotsByCustomer.keys) {
            final contextsCovered = spotsByCustomer[customerId]!
                .map((s) => s.inventoryContextId)
                .toSet();
            if (contextsCovered.length >= level) {
              candidateCustomer = customerId;
              break;
            }
          }

          if (candidateCustomer != null) {
            final spotsForCandidate =
                _groupSpotsByCustomer(availableSpots)[candidateCustomer]!;
            final candidateSpotsByContext =
                _groupSpotsByContext(spotsForCandidate);

            int numRowsPossible = -1;
            candidateSpotsByContext.forEach((_, spotsInContext) {
              if (numRowsPossible == -1 ||
                  spotsInContext.length < numRowsPossible) {
                numRowsPossible = spotsInContext.length;
              }
            });

            if (numRowsPossible > 0) {
              for (int i = 0; i < numRowsPossible; i++) {
                if (rowsForThisResource.length >= rowCount) break;

                final initialSpotsInRow = <int, SpotModel?>{};
                for (final contextId in candidateSpotsByContext.keys) {
                  // Find the spot using the typed Object key
                  final spotToUse = availableSpots.firstWhere((s) {
                    final sId = s.order?.id ?? _SpotIdentifier(s.id!);
                    return s.inventoryContextId == contextId &&
                        sId == candidateCustomer;
                  });
                  initialSpotsInRow[contextId] = spotToUse;
                  availableSpots.remove(spotToUse);
                }

                for (var context in bundle.inventoryContexts) {
                  initialSpotsInRow.putIfAbsent(context.id!, () => null);
                }

                rowsForThisResource.add(SpotMatrixRow(
                  rowReference: SpotManagementRowReference(
                      resource: resource,
                      initialSpotsInRow: initialSpotsInRow,
                      allSpotsMap: allSpotsMap),
                ));
              }
              wasRowBuiltInPass = true;
            }
          }
        } while (wasRowBuiltInPass);
      }

      // The rest of the logic (steps 3, 4, 5) remains unchanged as it doesn't
      // depend on the customer ID type.

      // 3. BACK-FILL
      if (availableSpots.isNotEmpty) {
        final remainingByContext = _groupSpotsByContext(availableSpots);
        for (final row in rowsForThisResource) {
          final rowRef = row.rowReference;
          final contextIds = rowRef.currentSpotsInRow.keys.toList();
          for (final contextId in contextIds) {
            if (rowRef.currentSpotsInRow[contextId] == null) {
              if (remainingByContext[contextId]?.isNotEmpty ?? false) {
                rowRef.currentSpotsInRow[contextId] =
                    remainingByContext[contextId]!.removeAt(0);
              }
            }
          }
        }
      }

      // 4. ADD EMPTY ROWS
      while (rowsForThisResource.length < rowCount) {
        rowsForThisResource.add(SpotMatrixRow(
          rowReference: SpotManagementRowReference(
              resource: resource,
              initialSpotsInRow: {
                for (var c in bundle.inventoryContexts) c.id!: null
              },
              allSpotsMap: allSpotsMap),
        ));
      }

      // 5. RE-NUMBER
      for (int i = 0; i < rowsForThisResource.length; i++) {
        final rowRef = rowsForThisResource[i].rowReference;
        if (slotsForResource.isNotEmpty) {
          if (i < slotsForResource.length) rowRef.slot = slotsForResource[i];
        } else {
          rowRef.implicitSlotIndex = i + 1;
        }
      }

      generatedRows.addAll(rowsForThisResource);
    }
    return generatedRows;
  }

  /// Clears all spot assignments by mutating the underlying models and then refreshing the UI.
  /// This function remains unchanged.
  Future<void> _clearAllAssignments(
      SingleDataGridController<ITrinaRowModel> controller) async {
    if (!mounted) return;

    final confirm = await DialogHelper.showConfirmationDialog(
      context,
      _clearAllTitle,
      _clearAllConfirmation,
    );

    if (confirm && mounted) {
      final stateManager = controller.stateManager;

      for (final row in stateManager.rows) {
        final rowRef = row.cells[SpotManagementConstants.rowReference]?.value
            as SpotManagementRowReference?;
        if (rowRef == null) continue;

        // 1. Mutate the data model for the entire row to be null.
        rowRef.currentSpotsInRow.updateAll((key, value) => null);

        // 2. Update the UI for each cell in the row.
        for (final cellEntry in row.cells.entries) {
          if (cellEntry.key
              .startsWith(SpotManagementConstants.contextColumnPrefix)) {
            stateManager.changeCellValue(cellEntry.value, '',
                force: true, notify: false);
          }
        }
      }
      // Notify the grid to re-render everything at once after all changes.
      stateManager.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller == null) {
      return Center(child: Text(InventoryStrings.spotManagementNoData));
    }
    return SingleTableDataGrid<SpotMatrixRow>(_controller!);
  }
}
