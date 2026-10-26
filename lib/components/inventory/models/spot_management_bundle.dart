import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/inventory/models/resource_slot_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';

class SpotManagementBundle {
  final List<SpotModel> spots;
  final List<InventoryContextModel> inventoryContexts;
  final List<ResourceModel> resources;
  final List<ResourceSlotModel> resourceSlots;
  final List<OrderProductTicketModel> orderProductTickets;
  final List<OrderModel> orders;

  SpotManagementBundle({
    required this.spots,
    required this.inventoryContexts,
    required this.resources,
    required this.resourceSlots,
    required this.orderProductTickets,
    required this.orders,
  });

  factory SpotManagementBundle.fromJson(Map<String, dynamic> json) {
    return SpotManagementBundle(
      spots: (json['spots'] as List)
          .map((i) => SpotModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      inventoryContexts: (json['inventory_contexts'] as List)
          .map((i) => InventoryContextModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      resources: (json['resources'] as List)
          .map((i) => ResourceModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      resourceSlots: (json['resource_slots'] as List)
          .map((i) => ResourceSlotModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      orderProductTickets: (json['order_product_tickets'] as List)
          .map((i) =>
              OrderProductTicketModel.fromJson(i as Map<String, dynamic>))
          .toList(),
      orders: (json['orders'] as List)
          .map((i) => OrderModel.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}
