import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/blueprint_group.dart';
import 'package:fstapp/components/blueprint/blueprint_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:collection/collection.dart';
import 'blueprint_strings.dart';
import 'blueprint_seat_state.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class BlueprintObjectModel {
  static const String metaX = "x";
  static const String metaY = "y";
  static const String metaSpot = "spot";
  static const String metaType = "type";
  static const String metaState = "state";
  static const String metaTitle = "title";
  static const String metaId = "id";
  static const String metaGroupId = "group";

  static const String orderedType = "ordered";
  static const String usedType = "used";
  static const String selectedType = "selected";
  static const String selectedByMeType = "selected_by_me";
  static const String blackType = "black";
  static const String availableType = "available";

  static Map<BlueprintSeatState, String> statesMap = {
    BlueprintSeatState.blocked: blackType,
    BlueprintSeatState.available: availableType,
    BlueprintSeatState.selected: selectedType,
    BlueprintSeatState.selectedByMe: selectedByMeType,
    BlueprintSeatState.ordered: orderedType,
    BlueprintSeatState.used: usedType,
  };

  @override
  toString() {
    return BlueprintStrings.objectModelToString(
      group?.title ?? '',
      title ?? '',
    );
  }

  int? x;
  int? y;
  int? id;
  int? groupId;
  int? orderProductTicket;
  String? type;
  String? state;
  String? title;
  ProductModel? product;
  int? spotProduct;
  BlueprintGroupModel? group;
  BlueprintSeatState? stateEnum;
  BlueprintModel? blueprint;

  int get seatRow =>
      y ?? (throw StateError('Blueprint seat is missing its row coordinate'));

  int get seatColumn =>
      x ??
      (throw StateError('Blueprint seat is missing its column coordinate'));

  BlueprintSeatState get seatState => stateEnum ?? BlueprintSeatState.empty;

  set seatState(BlueprintSeatState value) => setSeatState(value);

  factory BlueprintObjectModel.fromJson(Map<String, dynamic> json) {
    // Constructor will handle state/stateEnum sync
    return BlueprintObjectModel(
      x: json[metaX],
      y: json[metaY],
      id: json[metaId],
      groupId: json[metaGroupId],
      orderProductTicket: json[TbEshop.spots.order_product_ticket],
      type: json[metaType],
      state: json[metaState],
      title: json[metaTitle],
      spotProduct: json[TbEshop.spots.product],
    );
  }

  Map<String, dynamic> toJson() => {
        metaX: x,
        metaY: y,
        metaType: type,
        metaTitle: title,
        metaState: state, // Use the synced state string
        if (id != null) metaId: id,
        if (group?.id != null) metaGroupId: group?.id,
        if (spotProduct != null || product != null)
          TbEshop.spots.product: spotProduct ?? product?.id,
      };

  BlueprintObjectModel({
    this.x,
    this.y,
    this.id,
    this.groupId,
    this.orderProductTicket,
    this.type,
    this.state,
    this.stateEnum,
    this.title,
    this.spotProduct,
    this.product,
    this.blueprint,
  }) {
    // Ensure state and stateEnum are synchronized
    if (state != null && stateEnum == null) {
      stateEnum = statesMap.entries
          .firstWhere((entry) => entry.value == state,
              orElse: () => const MapEntry(BlueprintSeatState.empty, ""))
          .key;
    } else if (stateEnum != null && state == null) {
      state = statesMap[stateEnum];
    }
  }

  /// Updates both state and stateEnum
  void setSeatState(BlueprintSeatState newState) {
    stateEnum = newState;
    state = statesMap[newState];
  }

  String blueprintTooltip(BuildContext context) {
    // Find the matching order product ticket
    var opt = blueprint?.orderProductTickets
        ?.firstWhereOrNull((t) => t.id == orderProductTicket);

    if (opt != null) {
      // Find the corresponding ticket
      var ticket =
          blueprint?.tickets?.firstWhereOrNull((t) => t.id == opt.ticketId);

      if (ticket != null) {
        // Get other products associated with the ticket
        var otherProducts = blueprint?.orderProductTickets
            ?.where((o) => o.ticketId == ticket.id)
            .map((t) => t.productId)
            .toList();

        // Generate string for other products
        var productsString = otherProducts
                ?.where((p) => p != product?.id)
                .map((op) {
                  var pr = blueprint?.products?.firstWhere((p) => p.id == op);
                  return pr?.title ?? "";
                })
                .where((title) => title.isNotEmpty)
                .join("\n") ??
            "";

        // Get the order details
        var order = blueprint?.orders?.firstWhere((p) => p.id == opt.orderId);
        var orderNote = order?.toCustomerNote() ?? "";
        if (orderNote.isNotEmpty) {
          orderNote = "\n$orderNote";
        }
        var orderString =
            order != null ? "\n${order.toCustomerData()}$orderNote" : "";

        // Add ticket note if available
        var ticketNoteString = ticket.note != null && ticket.note!.isNotEmpty
            ? "\n${ticket.note}"
            : "";

        // Add hidden note if available
        var noteHiddenString =
            ticket.noteHidden != null && ticket.noteHidden!.isNotEmpty
                ? "\n(${ticket.noteHidden})"
                : "";

        final productsSection =
            productsString.isEmpty ? "" : "\n$productsString";
        return "${product?.title} ${title ?? ""}\n${OrdersStrings.itemSingular} ${ticket.ticketSymbol}$ticketNoteString$noteHiddenString$productsSection$orderString";
      }
    }

    // Fallback for when no matching ticket or order product ticket is found
    return "${product?.title} ${title ?? ""}\n${CommonStrings.price}: ${Utilities.formatPrice(context, product?.price ?? 0)}";
  }

  String getSwapSummary() {
    if (orderProductTicket != null) {
      var opt = blueprint?.orderProductTickets
          ?.firstWhereOrNull((t) => t.id == orderProductTicket);
      if (opt != null) {
        var order = blueprint?.orders?.firstWhere((p) => p.id == opt.orderId);
        var ticket =
            blueprint?.tickets?.firstWhereOrNull((t) => t.id == opt.ticketId);
        if (order != null && ticket != null) {
          return BlueprintStrings.swapSummaryCustomer(
              ticket.ticketSymbol ?? '?', order.toCustomerData());
        }
      }
      return BlueprintStrings.swapSummaryOccupied;
    }

    switch (stateEnum) {
      case BlueprintSeatState.available:
        return BlueprintStrings.swapSummaryAvailable;
      case BlueprintSeatState.blocked:
        return BlueprintStrings.swapSummaryBlack;
      case BlueprintSeatState.used:
        return BlueprintStrings.swapSummaryUsed;
      case BlueprintSeatState.selected:
      case BlueprintSeatState.selectedByMe:
        return BlueprintStrings.swapSummarySelected;
      default:
        return BlueprintStrings.swapSummaryEmpty;
    }
  }

  bool isOrdered() {
    return orderProductTicket != null;
  }

  String toSpotString() {
    return title ?? "";
  }
}
