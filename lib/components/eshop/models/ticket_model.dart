import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:trina_grid/trina_grid.dart';
import '../eshop_columns.dart';
import 'order_model.dart';
import '../../blueprint/blueprint_object_model.dart';
import 'product_model.dart';
import 'package:intl/intl.dart';

class TicketModel extends ITrinaRowModel {
  @override
  int? id;
  DateTime? createdAt;
  DateTime? updatedAt;
  String? ticketSymbol;
  String? state;
  int? occasion;
  String? note;
  String? noteHidden;
  double? totalPrice;

  // Relating spots, products, and orders directly to the ticket
  BlueprintObjectModel? relatedSpot;
  List<ProductModel>? relatedProducts;
  OrderModel? relatedOrder;

  List<UserGroupInfoModel>? relatedGroups;

  // Deposit info from scan response
  Map<String, dynamic>? depositInfo;

  TicketModel({
    this.id,
    this.createdAt,
    this.updatedAt,
    this.ticketSymbol,
    this.state,
    this.occasion,
    this.note,
    this.noteHidden,
    this.relatedSpot,
    this.relatedProducts,
    this.relatedOrder,
    this.relatedGroups,
    this.depositInfo,
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    return TicketModel(
      id: json[TbEshop.tickets.id],
      createdAt: json[TbEshop.tickets.created_at] != null
          ? DateTime.parse(json[TbEshop.tickets.created_at]).toOccasionTime()
          : null,
      updatedAt: json[TbEshop.tickets.updated_at] != null
          ? DateTime.parse(json[TbEshop.tickets.updated_at]).toOccasionTime()
          : null,
      ticketSymbol: json[TbEshop.tickets.ticket_symbol],
      state: json[TbEshop.tickets.state],
      occasion: json[TbEshop.tickets.occasion],
      note: json[TbEshop.tickets.note],
      noteHidden: json[TbEshop.tickets.note_hidden],
    );
  }

  Map<String, dynamic> toJson() => {
        TbEshop.tickets.state: state,
        TbEshop.tickets.note_hidden: noteHidden,
      };

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    Map<String, TrinaCell> cells = {
      EshopColumns.TICKET_ID: TrinaCell(value: id ?? 0),
      EshopColumns.TICKET_CREATED_AT: TrinaCell(
          value: createdAt != null
              ? DateFormat('yyyy-MM-dd').format(createdAt!)
              : ""),
      EshopColumns.TICKET_LAST_CHANGE: TrinaCell(
          value: updatedAt != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(updatedAt!)
              : ""),
      EshopColumns.TICKET_SYMBOL: TrinaCell(value: ticketSymbol ?? ""),
      EshopColumns.TICKET_STATE: TrinaCell(
          value: OrderModel.formatState(state ?? OrderModel.orderedState)),
      EshopColumns.TICKET_DOWNLOAD: TrinaCell(value: ""),
      EshopColumns.TICKET_NOTE: TrinaCell(
          value: Utilities.removeTabsAndNewLines(note ?? "")),
      EshopColumns.TICKET_NOTE_HIDDEN: TrinaCell(
          value: Utilities.removeTabsAndNewLines(noteHidden ?? "")),
      EshopColumns.ORDER_SEQUENCE: TrinaCell(
        value: relatedOrder?.orderSequence,
      ),
      EshopColumns.ORDER_MODEL_REFERENCE: TrinaCell(value: relatedOrder),
      EshopColumns.ORDER_SYMBOL: TrinaCell(
          value: relatedOrder != null ? relatedOrder!.toBasicString() : ""),
      EshopColumns.ORDER_DATA: TrinaCell(
          value: relatedOrder != null ? relatedOrder!.toCustomerData() : ""),
      EshopColumns.TICKET_PRODUCTS: TrinaCell(
          value: relatedProducts != null
              ? relatedProducts!.map((p) => p.toBasicString()).join(" | ")
              : ""),
      EshopColumns.TICKET_SPOT: TrinaCell(
          value: relatedSpot != null ? relatedSpot?.toSpotString() : ""),
      EshopColumns.TICKET_TOTAL_PRICE: TrinaCell(
          value: totalPrice != null
              ? Utilities.formatPrice(context, totalPrice!,
                  currencyCode: relatedOrder?.currencyCode)
              : ""),
      EshopColumns.TICKET_PRODUCTS_EDIT: TrinaCell(value: ""),
      EshopColumns.TICKET_CONFIRM: TrinaCell(value: ""),
    };

    final productCells =
        EshopColumns.generateProductTypeCells(relatedProducts ?? []);
    cells.addAll(productCells);
    return TrinaRow(cells: cells);
  }

  static TicketModel fromPlutoJson(Map<String, dynamic> json) {
    return TicketModel(
        id: json[EshopColumns.TICKET_ID] == -1
            ? null
            : json[EshopColumns.TICKET_ID],
        noteHidden: json[EshopColumns.TICKET_NOTE_HIDDEN]);
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    // Implement your delete logic here
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbTickets.updateTicketNoteHidden(id!, noteHidden!);
  }

  @override
  String toBasicString() => ticketSymbol ?? id.toString();
}
