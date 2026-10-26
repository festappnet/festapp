import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/inventory/models/resource_slot_model.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:trina_grid/trina_grid.dart';

/// Represents a reservable spot within the e-shop context, such as a seat,
/// a room, or any other unique, bookable item.
class SpotModel extends ITrinaRowModel {
  @override
  int? id;
  final DateTime? createdAt;
  final int? occasionId;
  final int? productId;
  final DateTime? updatedAt;
  final String? secret;
  final DateTime? secretExpirationTime;
  String? title;
  final int? orderProductTicketId;
  final int? blueprintId;
  int? inventoryContextId;
  int? resourceId;
  int? resourceSlotId;
  String? state;

  // Navigation properties populated after fetching the bundle.
  InventoryContextModel? inventoryContext;
  ResourceModel? resource;
  ResourceSlotModel? resourceSlot;
  OrderProductTicketModel? orderProductTicket;
  OrderModel? order;
  ProductModel? product; // New navigation property

  SpotModel({
    this.id,
    this.createdAt,
    this.occasionId,
    this.productId,
    this.updatedAt,
    this.secret,
    this.secretExpirationTime,
    this.title,
    this.orderProductTicketId,
    this.blueprintId,
    this.inventoryContextId,
    this.resourceId,
    this.resourceSlotId,
    this.state,
    this.inventoryContext,
    this.resource,
    this.resourceSlot,
    this.orderProductTicket,
    this.order,
    this.product, // Added to constructor
  });

  /// Creates a SpotModel instance from a JSON map from the database.
  factory SpotModel.fromJson(Map<String, dynamic> json) {
    final t = TbEshop.spots;
    return SpotModel(
      id: json[t.id],
      createdAt: json[t.created_at] != null
          ? DateTime.parse(json[t.created_at])
          : null,
      occasionId: json[t.occasion],
      productId: json[t.product],
      updatedAt: json[t.updated_at] != null
          ? DateTime.parse(json[t.updated_at])
          : null,
      secret: json[t.secret],
      secretExpirationTime: json[t.secret_expiration_time] != null
          ? DateTime.parse(json[t.secret_expiration_time])
          : null,
      title: json[t.title],
      orderProductTicketId: json[t.order_product_ticket],
      blueprintId: json[t.blueprint],
      inventoryContextId: json[t.inventory_context],
      resourceId: json[t.resource],
      resourceSlotId: json[t.resource_slot],
      state: json[t.state],
    );
  }

  /// Creates a SpotModel instance from a TrinaGrid row's JSON data.
  static SpotModel fromPlutoJson(Map<String, dynamic> json) {
    final t = TbEshop.spots;
    return SpotModel(
      id: json[t.id],
      title: json[t.title],
      state: json[t.state],
      inventoryContextId: json[t.inventory_context],
      resourceId: json[t.resource],
      resourceSlotId: json[t.resource_slot],
    );
  }

  /// Converts this SpotModel instance to a JSON map for database operations.
  Map<String, dynamic> toJson() {
    final t = TbEshop.spots;
    return {
      t.id: id,
      t.occasion: occasionId,
      t.product: productId,
      t.title: title,
      t.order_product_ticket: orderProductTicketId,
      t.blueprint: blueprintId,
      t.inventory_context: inventoryContextId,
      t.resource: resourceId,
      t.resource_slot: resourceSlotId,
      t.state: state,
    };
  }

  @override
  String toBasicString() => title ?? id.toString();

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    final t = TbEshop.spots;
    Map<String, TrinaCell> cells = {
      t.id: TrinaCell(value: id ?? 0),
      t.title: TrinaCell(value: title ?? ""),
      t.state: TrinaCell(value: state ?? ""),
      // Added product display to the grid row
      t.product: TrinaCell(value: product?.toBasicString() ?? productId),
      t.inventory_context:
          TrinaCell(value: inventoryContext?.title ?? inventoryContextId),
      t.resource: TrinaCell(value: resource?.title ?? resourceId),
      t.resource_slot: TrinaCell(value: resourceSlot?.title ?? resourceSlotId),
      "order": TrinaCell(
          value: order?.toBasicString() ??
              (orderProductTicketId != null
                  ? "Order ID: ${orderProductTicket?.orderId}"
                  : "")),
    };
    return TrinaRow(cells: cells);
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    if (id != null) {
      // In a real implementation, you would have a DbSpots.deleteSpot(id!) method.
    }
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    // In a real implementation, you would have a DbSpots.updateSpot(this) method.
  }
}
