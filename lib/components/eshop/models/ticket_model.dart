import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:trina_grid/trina_grid.dart';
import '../eshop_columns.dart';
import '../ticket_batch_strings.dart';
import 'order_model.dart';
import '../../blueprint/blueprint_object_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:intl/intl.dart';

class TicketModel extends ITrinaRowModel {
  @override
  int? id;
  DateTime? createdAt;
  DateTime? updatedAt;
  String? ticketSymbol;
  String? state;
  int? occasion;
  Map<String, dynamic>? batch;
  Set<String>? allowedActions;
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
    this.batch,
    this.allowedActions,
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
      allowedActions: (json['allowedActions'] as List?)?.cast<String>().toSet(),
      batch: json['batch'] == null
          ? null
          : Map<String, dynamic>.from(json['batch']),
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
      EshopColumnIds.TICKET_ORIGIN: TrinaCell(
          value: TicketBatchStrings.text(batch == null ? 'ordinary' : 'title')),
      EshopColumnIds.TICKET_BATCH: TrinaCell(value: batch?['title'] ?? ''),
      EshopColumnIds.TICKET_SALE_STATE: TrinaCell(
          value: batch == null
              ? ''
              : TicketBatchStrings.text(state == 'storno'
                  ? 'voided'
                  : batch?['saleOrderId'] == null
                      ? 'available'
                      : 'sold')),
      EshopColumnIds.TICKET_ID: TrinaCell(value: id ?? 0),
      EshopColumnIds.TICKET_MODEL_REFERENCE: TrinaCell(value: this),
      EshopColumnIds.TICKET_CREATED_AT: TrinaCell(
          value: createdAt != null
              ? DateFormat('yyyy-MM-dd').format(createdAt!)
              : ""),
      EshopColumnIds.TICKET_LAST_CHANGE: TrinaCell(
          value: updatedAt != null
              ? DateFormat('yyyy-MM-dd HH:mm').format(updatedAt!)
              : ""),
      EshopColumnIds.TICKET_SYMBOL: TrinaCell(value: ticketSymbol ?? ""),
      EshopColumnIds.TICKET_STATE: TrinaCell(
          value: OrderModel.formatState(state ?? OrderModel.orderedState)),
      EshopColumnIds.TICKET_DOWNLOAD: TrinaCell(value: ""),
      EshopColumnIds.TICKET_NOTE:
          TrinaCell(value: Utilities.removeTabsAndNewLines(note ?? "")),
      EshopColumnIds.TICKET_NOTE_HIDDEN:
          TrinaCell(value: Utilities.removeTabsAndNewLines(noteHidden ?? "")),
      EshopColumnIds.ORDER_SEQUENCE: TrinaCell(
        value: relatedOrder?.orderSequence,
      ),
      EshopColumnIds.ORDER_MODEL_REFERENCE: TrinaCell(value: relatedOrder),
      EshopColumnIds.ORDER_SYMBOL:
          TrinaCell(value: relatedOrder?.orderSymbol ?? ""),
      EshopColumnIds.ORDER_DATA: TrinaCell(
          value: relatedOrder != null ? relatedOrder!.toCustomerData() : ""),
      EshopColumnIds.TICKET_PRODUCTS: TrinaCell(
          value: relatedProducts != null
              ? relatedProducts!.map((p) => p.toBasicString()).join(" | ")
              : ""),
      EshopColumnIds.TICKET_SPOT: TrinaCell(
          value: relatedSpot != null ? relatedSpot?.toSpotString() : ""),
      EshopColumnIds.TICKET_TOTAL_PRICE: TrinaCell(
          value: totalPrice != null
              ? Utilities.formatPrice(context, totalPrice!,
                  currencyCode: relatedOrder?.currencyCode,
                  decimalDigits: relatedOrder?.amountDecimalDigits ?? 0)
              : ""),
      EshopColumnIds.TICKET_PRODUCTS_EDIT: TrinaCell(value: ""),
      EshopColumnIds.TICKET_CONFIRM: TrinaCell(value: ""),
    };

    final productCells =
        EshopColumns.generateProductTypeCells(relatedProducts ?? []);
    cells.addAll(productCells);
    return TrinaRow(cells: cells);
  }

  static TicketModel fromPlutoJson(Map<String, dynamic> json) {
    final original =
        json[EshopColumnIds.TICKET_MODEL_REFERENCE] as TicketModel?;
    return TicketModel(
        id: json[EshopColumnIds.TICKET_ID] == -1
            ? null
            : json[EshopColumnIds.TICKET_ID],
        ticketSymbol: json[EshopColumnIds.TICKET_SYMBOL] as String?,
        relatedOrder: json[EshopColumnIds.ORDER_MODEL_REFERENCE] as OrderModel?,
        relatedSpot: original?.relatedSpot,
        relatedProducts: original?.relatedProducts,
        noteHidden: json[EshopColumnIds.TICKET_NOTE_HIDDEN]);
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
  String toBasicString() => [
        if (ticketSymbol?.trim().isNotEmpty == true)
          ticketSymbol!.trim()
        else if (id != null)
          '#$id',
        if (relatedSpot?.toSpotString().trim().isNotEmpty == true)
          relatedSpot!.toSpotString().trim(),
        ...?relatedProducts
            ?.map((product) => product.toBasicString().trim())
            .where((label) => label.isNotEmpty),
      ].join(' - ');
}
