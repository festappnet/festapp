import 'package:fstapp/components/occasion/occasion_model.dart';
import 'inventory_context_stock.dart';
import 'inventory_pool_model.dart';

/// Current stock-card summary. Raw spots and hold secrets stay out of this view.
class InventoryPoolsListBundle {
  final OccasionModel occasion;
  final List<InventoryPoolModel> pools;
  final List<InventoryContextStock> contextStocks;

  InventoryPoolsListBundle(
      {required this.occasion,
      required this.pools,
      required this.contextStocks});

  factory InventoryPoolsListBundle.fromJson(Map<String, dynamic> json) {
    final pools = (json['pools'] as List)
        .map((p) => InventoryPoolModel.fromJson(p))
        .toList();
    final byId = {for (final pool in pools) pool.id: pool};
    final contexts = (json['inventory_contexts'] as List)
        .map((c) => InventoryContextStock.fromJson(c))
        .toList();
    for (final stock in contexts) {
      stock.context.inventoryPool = byId[stock.context.inventoryPoolId];
    }
    return InventoryPoolsListBundle(
        occasion: OccasionModel.fromJson(json['occasion']),
        pools: pools,
        contextStocks: contexts);
  }
}
