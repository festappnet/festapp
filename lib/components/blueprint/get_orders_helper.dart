import 'package:collection/collection.dart';

import 'blueprint_seat_state.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/product_type_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/user_info_model.dart';

class GetOrdersHelper {
  static List<BlueprintGroupModel> parseGroups(Map<String, dynamic> json) {
    return json[TbEshop.blueprints.groups] != null
        ? List<BlueprintGroupModel>.from(json[TbEshop.blueprints.groups]
            .map((g) => BlueprintGroupModel.fromJson(g)))
        : [];
  }

  static List<BlueprintObjectModel>? parseObjects(Map<String, dynamic> json) {
    return json[TbEshop.blueprints.objects] != null
        ? List<BlueprintObjectModel>.from(json[TbEshop.blueprints.objects]
            .map((obj) => BlueprintObjectModel.fromJson(obj)))
        : null;
  }

  static List<BlueprintObjectModel>? parseSpots(Map<String, dynamic> json) {
    return json[BlueprintModel.metaSpots] != null
        ? List<BlueprintObjectModel>.from(json[BlueprintModel.metaSpots]
            .map((spot) => BlueprintObjectModel.fromJson(spot)))
        : null;
  }

  static List<ProductModel>? parseProducts(Map<String, dynamic> json) {
    return json[TbEshop.products.table] != null
        ? List<ProductModel>.from(
            json[TbEshop.products.table].map((p) => ProductModel.fromJson(p)))
        : null;
  }

  static List<ProductTypeModel>? parseProductTypes(Map<String, dynamic> json) {
    return json[TbEshop.product_types.table] != null
        ? List<ProductTypeModel>.from(json[TbEshop.product_types.table]
            .map((pt) => ProductTypeModel.fromJson(pt)))
        : null;
  }

  static List<TicketModel>? parseTickets(Map<String, dynamic> json) {
    return json[TbEshop.tickets.table] != null
        ? List<TicketModel>.from(
            json[TbEshop.tickets.table].map((t) => TicketModel.fromJson(t)))
        : null;
  }

  static List<OrderModel>? parseOrders(Map<String, dynamic> json) {
    return json[TbEshop.orders.table] != null
        ? List<OrderModel>.from(
            json[TbEshop.orders.table].map((o) => OrderModel.fromCanonicalJson(o)))
        : null;
  }

  static List<OrderProductTicketModel>? parseOrderProductTickets(
      Map<String, dynamic> json) {
    return json[TbEshop.order_product_ticket.table] != null
        ? List<OrderProductTicketModel>.from(
            json[TbEshop.order_product_ticket.table]
                .map((o) => OrderProductTicketModel.fromJson(o)))
        : null;
  }

  static List<PaymentInfoModel>? parsePaymentInfo(Map<String, dynamic> json) {
    return json[TbEshop.payment_info.table] != null
        ? List<PaymentInfoModel>.from(json[TbEshop.payment_info.table]
            .map((g) => PaymentInfoModel.fromJson(g)))
        : [];
  }

  static List<FormModel>? parseForms(Map<String, dynamic> json) {
    return json[Tb.forms.table] != null
        ? List<FormModel>.from(
            json[Tb.forms.table].map((g) => FormModel.fromJson(g)))
        : [];
  }

  static List<OrderHistoryModel>? parseOrdersHistory(
      Map<String, dynamic> json) {
    return json[TbEshop.orders_history.table] != null
        ? List<OrderHistoryModel>.from(json[TbEshop.orders_history.table]
            .map((o) => OrderHistoryModel.fromJson(o)))
        : null;
  }

  static List<UserInfoModel>? parseUsers(Map<String, dynamic> json) {
    return json["users"] != null
        ? List<UserInfoModel>.from(
            json["users"].map((u) => UserInfoModel.fromJson(u)))
        : null;
  }

  static List<BlueprintObjectModel>? enrichObjects(
    List<BlueprintObjectModel>? rawObjects,
    List<BlueprintObjectModel>? spots,
    List<ProductModel>? products,
  ) {
    if (rawObjects == null) return null;

    return rawObjects
        .map((object) {
          if (object.type == BlueprintModel.metaSpotType) {
            final matchingSpot =
                spots?.firstWhereOrNull((spot) => spot.id == object.id);
            return BlueprintObjectModel(
              id: object.id,
              type: object.type,
              spotProduct: matchingSpot?.spotProduct,
              product: products
                  ?.firstWhereOrNull((p) => p.id == matchingSpot?.spotProduct),
              orderProductTicket: matchingSpot?.orderProductTicket,
              groupId: object.groupId,
              title: matchingSpot?.title ?? object.title,
              stateEnum: BlueprintObjectModel.statesMap.entries
                      .firstWhereOrNull(
                          (entry) => entry.value == matchingSpot?.state)
                      ?.key ??
                  BlueprintSeatState.available,
              x: object.x,
              y: object.y,
            );
          } else if (object.type == BlueprintModel.metaTableAreaType) {
            return BlueprintObjectModel(
              id: object.id,
              type: object.type,
              title: object.title,
              stateEnum: BlueprintSeatState.blocked,
              x: object.x,
              y: object.y,
            );
          }
          return null; // Skip unrecognized object types
        })
        .whereType<BlueprintObjectModel>()
        .toList(); // Filter out null values
  }

  static void assignObjectsToGroups(
    List<BlueprintObjectModel>? objects,
    List<BlueprintGroupModel>? groups,
  ) {
    if (objects != null) {
      for (var obj in objects) {
        if (obj.groupId != null) {
          final group = groups?.firstWhereOrNull((g) => g.id == obj.groupId);
          obj.group = group;
          if (group != null) {
            group.objects.add(obj);
          }
        }
      }
    }
  }
}
