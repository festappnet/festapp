import 'package:festapp_core/eshop.dart';
import 'inventory_context_model.dart';
import 'inventory_pool_model.dart';
import 'resource_model.dart';

/// Authoritative saved aggregate returned by one standing-preparation command.
class StandingInventoryPreparation {
  const StandingInventoryPreparation(
      {required this.product,
      required this.pool,
      required this.context,
      required this.resource});
  final ProductModel product;
  final InventoryPoolModel pool;
  final InventoryContextModel context;
  final ResourceModel resource;

  factory StandingInventoryPreparation.fromJson(Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data['product'] as Map);
    final pool = InventoryPoolModel.fromJson(
        Map<String, dynamic>.from(data['pool'] as Map));
    final context = InventoryContextModel.fromJson(
        Map<String, dynamic>.from(data['context'] as Map))
      ..inventoryPool = pool;
    final formTitles = {
      for (final form in data['forms'] as List)
        form['id']: form['title'] ?? '---'
    };
    final readAt = DateTime.parse(data['readAt'] as String).toUtc();
    return StandingInventoryPreparation(
      product: ProductModel.fromJson(raw).copyWith(
          formTitles: [
            for (final id in raw['form_ids'] as List) formTitles[id] ?? '---'
          ].join(', '),
          priceServerTime: readAt,
          priceClockOffset: readAt.difference(DateTime.now().toUtc()),
          includedInventories: [
            for (final link in raw['inventory_contexts'] as List)
              ProductInventoryContextModel(
                  productId: raw['id'],
                  inventoryContextId: link['inventory_context_id'],
                  quantity: link['quantity'])
          ]),
      pool: pool,
      context: context,
      resource: ResourceModel.fromJson(
          Map<String, dynamic>.from(data['resource'] as Map)),
    );
  }
}
