import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/inventory/models/resource_slot_model.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';

/// A unified object to hold all reference data for a single row in the spot management grid.
/// This is passed in a single hidden column to simplify data access in renderers and dialogs.
class SpotManagementRowReference {
  final ResourceModel resource;
  ResourceSlotModel? slot;
  int? implicitSlotIndex;

  /// The original state of spots in the row when the data was loaded. Used for comparison during updates.
  final Map<int, SpotModel?> initialSpotsInRow;

  /// The complete map of all available spots, used for lookups in dialogs.
  final Map<int, SpotModel> allSpotsMap;

  /// The current state of spots in the row, which can be modified by the user.
  Map<int, SpotModel?> currentSpotsInRow;

  SpotManagementRowReference({
    required this.resource,
    this.slot,
    this.implicitSlotIndex,
    required this.initialSpotsInRow,
    required this.allSpotsMap,
  }) : currentSpotsInRow = Map.from(
            initialSpotsInRow); // Initialize current state from initial state
}
