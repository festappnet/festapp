import 'inventory_context_model.dart';

/// SQL-owned administration counts for one inventory context. These count
/// physical/allocated spots, not distinct people or orders.
class InventoryContextStock {
  const InventoryContextStock(
      {required this.context,
      required this.physicalCount,
      required this.allocatedCount,
      required this.unassignedCount,
      required this.heldCount});
  final InventoryContextModel context;
  final int physicalCount;
  final int allocatedCount;
  final int unassignedCount;
  final int heldCount;
  factory InventoryContextStock.fromJson(Map<String, dynamic> json) =>
      InventoryContextStock(
          context: InventoryContextModel.fromJson(json),
          physicalCount: json['physical_count'] as int,
          allocatedCount: json['allocated_count'] as int,
          unassignedCount: json['unassigned_count'] as int,
          heldCount: json['held_count'] as int);
}
