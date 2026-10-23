import 'waitlist_summary_model.dart';
import '../../forms/waitlist_strings.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/eshop/eshop_column_ids.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/forms/models/form_bundle.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:trina_grid/trina_grid.dart';

import 'order_data_ticket_model.dart';
import 'orders_history_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class OrderModel extends ITrinaRowModel {
  @override
  int? id;
  String? orderSymbol;
  int? orderSequence;
  DateTime? createdAt;
  DateTime? updatedAt;
  double? price;
  String? state;
  WaitlistSummaryModel? waitlistSummary;
  bool? active;
  Set<String>? allowedActions;
  bool get isWaitlisted => state == waitlistedState;
  String get stateLabel {
    final counts = waitlistSummary?.counts;
    if (isWaitlisted &&
        counts != null &&
        counts.values.fold<int>(0, (sum, count) => sum + count) == 1 &&
        counts['offered'] == 1) {
      return WaitlistStrings.text('offered');
    }
    return stateToLocale(state);
  }

  bool get isActive =>
      active ??
      waitlistSummary?.isActive ??
      (!isWaitlisted && state != stornoState);
  bool allows(String action) {
    final actions = allowedActions ?? waitlistSummary?.allowedActions;
    if (actions != null) return actions.contains(action);
    if (state == 'stock' ||
        isWaitlisted ||
        state == stornoState ||
        state == 'preparing_payment') return action == 'view';
    return switch (action) {
      'view' || 'note' || 'edit' || 'cancel' => true,
      'paid' => state == orderedState,
      'send' => [orderedState, paidState, sentState, usedState, expiredState]
          .contains(state),
      _ => false,
    };
  }

  /// Payment changes use the same mutable ordinary-order states as transactions.
  /// Adding a receipt is distinct from the action that marks an order paid.
  static bool canChangePaymentInState(String? state) =>
      state != null &&
      ![waitlistedState, stornoState, 'preparing_payment'].contains(state);
  bool get canChangePayment => canChangePaymentInState(state) && allows('edit');

  /// Warn only while the order is awaiting a bank payment. Completed states
  /// stay quiet even if historical ledger amounts differ from the order price.
  BankSyncWarning? get bankSyncWarning {
    final payment = paymentInfoModel;
    if (!isActive ||
        ![
          orderedState,
          expiredState,
        ].contains(state) ||
        payment?.bankAccount == null ||
        (payment!.amount ?? 0) <= (payment.paid ?? 0)) {
      return null;
    }
    return payment.bankSyncWarning;
  }

  bool get canEdit => allows('edit');
  Map<String, dynamic>? data;
  int? occasion;
  int? paymentInfo;
  String? formKey;
  int? formId;
  String? currencyCode;
  // Read-only payment method supplied by authorized order/history projections.
  String? paymentMethod;
  String? paymentChannel;
  bool get isStripePayment =>
      (paymentInfoModel?.paymentMethod ?? paymentMethod) == 'stripe';
  int get amountDecimalDigits => isStripePayment ? 2 : 0;
  String? noteHidden;
  Map<String, dynamic>? emailDelivery;

  // Relating to top-level DB tables
  FormBundle? form;
  List<TicketModel>? relatedTickets;
  List<BlueprintObjectModel>? relatedSpots;
  List<ProductModel>? relatedProducts;
  PaymentInfoModel? paymentInfoModel;
  List<OrderHistoryModel>? relatedHistory;
  // Parsed from the 'data' JSON field
  List<OrderDataTicketModel>? dataTickets;

  static const String waitlistedState = "waitlisted";
  static const String expiredState = "expired";
  static const String orderedState = "ordered";
  static const String paidState = "paid";
  static const String sentState = "sent";
  static const String usedState = "used";
  static const String stornoState = "storno";
  static const orderStates = [
    waitlistedState,
    expiredState,
    orderedState,
    paidState,
    sentState,
    usedState,
    stornoState
  ];

  static String stateToLocale(String? state) {
    if (state == null || state.isEmpty) return OrdersStrings.stateNotSet;
    switch (state) {
      case waitlistedState:
        return WaitlistStrings.text('orderState');
      case orderedState:
      case expiredState:
        return OrdersStrings.stateOrdered;
      case paidState:
        return OrdersStrings.paid;
      case sentState:
        return OrdersStrings.stateSent;
      case usedState:
        return OrdersStrings.stateUsed;
      case stornoState:
        return CommonStrings.storno;
      default:
        return state; // Return the key itself if not found
    }
  }

  static String statesDataGridToUpper(String state) {
    String firstPart = state.split(";")[0];
    return stateToLocale(firstPart).toUpperCase();
  }

  static List<String> statesToDataGridFormat() {
    return OrderModel.orderStates.map(formatState).toList();
  }

  static String formatState(String state) {
    return "$state;${OrderModel.stateToLocale(state)}";
  }

  bool isExpired() {
    if (state != orderedState ||
        paymentInfoModel == null ||
        paymentInfoModel!.deadline == null) {
      return false;
    }
    // Create date-only objects for now and for the deadline.
    final nowDate = DateTime(
        TimeHelper.now().year, TimeHelper.now().month, TimeHelper.now().day);
    final deadlineDate = DateTime(paymentInfoModel!.deadline!.year,
        paymentInfoModel!.deadline!.month, paymentInfoModel!.deadline!.day);
    return nowDate.isAfter(deadlineDate);
  }

  static Color singleDataGridStateToColor(String state) {
    Color color;
    String firstPart = state.split(";")[0];
    switch (firstPart) {
      case waitlistedState:
        color = Colors.amber[700]!;
        break;
      case expiredState:
      case orderedState:
        color = Colors.green[100]!; // Blue for ordered
        break;
      case paidState:
        color = Colors.green[300]!; // A darker shade of green for paid
        break;
      case sentState:
        color = Colors.green[800]!; // Orange for sent
        break;
      case usedState:
        color = Colors.blue[600]!; // A darker shade of grey for used
        break;
      case stornoState:
        color =
            Colors.grey[700]!; // A lighter shade of green for canceled (storno)
        break;
      default:
        color = Colors.black; // Black for unknown states
    }

    // Apply global opacity to all colors
    return color.withValues(alpha: 0.6);
  }

  OrderModel({
    this.waitlistSummary,
    this.active,
    this.allowedActions,
    this.id,
    this.orderSymbol,
    this.orderSequence,
    this.createdAt,
    this.updatedAt,
    this.price,
    this.state,
    this.data,
    this.occasion,
    this.paymentInfo,
    this.formKey,
    this.formId,
    this.currencyCode,
    this.paymentMethod,
    this.paymentChannel,
    this.noteHidden,
    this.form,
    this.relatedTickets,
    this.relatedSpots,
    this.relatedProducts,
    this.paymentInfoModel,
    this.relatedHistory,
    this.dataTickets,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    // Logic to parse the nested tickets from the 'data' field
    List<OrderDataTicketModel>? parsedDataTickets;
    final orderData = json[TbEshop.orders.data];
    if (orderData is Map<String, dynamic> && orderData['tickets'] is List) {
      parsedDataTickets = (orderData['tickets'] as List)
          .map((t) => OrderDataTicketModel.fromJson(t as Map<String, dynamic>))
          .toList();
    }

    return OrderModel(
      waitlistSummary: json['waitlistSummary'] is Map<String, dynamic>
          ? WaitlistSummaryModel.fromJson(json['waitlistSummary'])
          : null,
      active: json['isActive'],
      allowedActions: json['allowedActions'] is List
          ? Set<String>.from(json['allowedActions'])
          : null,
      id: json[TbEshop.orders.id],
      orderSymbol: json[TbEshop.orders.order_symbol] as String?,
      orderSequence: (json[TbEshop.orders.order_sequence] as num?)?.toInt(),
      createdAt: json[TbEshop.orders.created_at] != null
          ? DateTime.parse(json[TbEshop.orders.created_at])
          : null,
      updatedAt: json[TbEshop.orders.updated_at] != null
          ? DateTime.parse(json[TbEshop.orders.updated_at])
          : null,
      price: json[TbEshop.orders.price] != null
          ? double.tryParse(json[TbEshop.orders.price].toString())
          : null,
      currencyCode: json[TbEshop.orders.currency_code],
      paymentMethod: json['payment_method'] as String?,
      paymentChannel: json['paymentChannel'] as String?,
      state: json[TbEshop.orders.state],
      formKey: orderData is Map<String, dynamic>
          ? orderData[TbEshop.orders.data_form]
          : null,
      formId: (json['form'] != null &&
              json['form'] is Map &&
              json['form'][Tb.forms.id] != null)
          ? json['form'][Tb.forms.id]
          : (json['form_id']),
      data: orderData,
      occasion: json[TbEshop.orders.occasion],
      paymentInfo: json[TbEshop.orders.payment_info],
      noteHidden: json[TbEshop.orders.note_hidden],
      dataTickets: parsedDataTickets,
    );
  }

  static OrderModel fromCanonicalJson(Map<String, dynamic> json) {
    final sequence = json[TbEshop.orders.order_sequence];
    if (sequence is! num || sequence <= 0) {
      throw StateError(
        'Canonical order response requires positive order_sequence',
      );
    }
    return OrderModel.fromJson(json);
  }

  static OrderModel fromPlutoJson(Map<String, dynamic> json) {
    return OrderModel(
        id: json[EshopColumnIds.ORDER_ID] == -1
            ? null
            : json[EshopColumnIds.ORDER_ID],
        orderSymbol: json[EshopColumnIds.ORDER_SYMBOL] as String?,
        data: {
          'name': json[EshopColumnIds.ORDER_DATA] as String?,
          'email': json[EshopColumnIds.ORDER_EMAIL] as String?,
        },
        noteHidden: json[EshopColumnIds.ORDER_NOTE_HIDDEN]);
  }

  Map<String, dynamic> toJson() => {
        'waitlistSummary': waitlistSummary?.toJson(),
        'isActive': isActive,
        'allowedActions': allowedActions?.toList(),
        TbEshop.orders.id: id,
        TbEshop.orders.created_at: createdAt?.toIso8601String(),
        TbEshop.orders.updated_at: updatedAt?.toIso8601String(),
        TbEshop.orders.price: price,
        TbEshop.orders.state: state,
        TbEshop.orders.data: data,
        TbEshop.orders.occasion: occasion,
        TbEshop.orders.payment_info: paymentInfo,
        TbEshop.orders.currency_code: currencyCode,
        TbEshop.orders.note_hidden: noteHidden,
      };

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    return TrinaRow(cells: {
      EshopColumnIds.ORDER_WAITLIST:
          TrinaCell(value: waitlistSummary?.label ?? ''),
      EshopColumnIds.ORDER_ID: TrinaCell(value: id ?? 0),
      EshopColumnIds.ORDER_SEQUENCE: TrinaCell(value: orderSequence),
      EshopColumnIds.ORDER_SYMBOL: TrinaCell(value: orderSymbol ?? ""),
      EshopColumnIds.ORDER_PRICE: TrinaCell(
          value: price != null
              ? Utilities.formatPrice(context, price!,
                  currencyCode: currencyCode,
                  decimalDigits: amountDecimalDigits)
              : ""),
      EshopColumnIds.ORDER_STATE:
          TrinaCell(value: OrderModel.formatState(state ?? orderedState)),
      EshopColumnIds.PAYMENT_INFO_AMOUNT: TrinaCell(
          value: paymentInfoModel?.amount != null
              ? Utilities.formatPrice(context, paymentInfoModel!.amount!,
                  currencyCode: paymentInfoModel!.currencyCode,
                  decimalDigits: amountDecimalDigits)
              : ""),
      EshopColumnIds.PAYMENT_INFO_PAID: TrinaCell(
          value: paymentInfoModel?.paid != null
              ? Utilities.formatPrice(context, paymentInfoModel!.paid!,
                  currencyCode: paymentInfoModel!.currencyCode,
                  decimalDigits: amountDecimalDigits)
              : ""),
      EshopColumnIds.PAYMENT_INFO_ID: TrinaCell(value: paymentInfo ?? 0),
      EshopColumnIds.PAYMENT_INFO_RETURNED: TrinaCell(
          value: paymentInfoModel?.returned != null
              ? Utilities.formatPrice(context, paymentInfoModel!.returned!,
                  currencyCode: paymentInfoModel!.currencyCode,
                  decimalDigits: amountDecimalDigits)
              : ""),
      EshopColumnIds.PAYMENT_INFO_VARIABLE_SYMBOL:
          TrinaCell(value: paymentInfoModel?.variableSymbol ?? 0),
      EshopColumnIds.PAYMENT_INFO_DEADLINE: TrinaCell(
        value: paymentInfoModel?.deadline != null
            ? DateFormat('yyyy-MM-dd').format(paymentInfoModel!.deadline!)
            : "",
      ),
      EshopColumnIds.PAYMENT_INFO_DEPOSIT_DEADLINE: TrinaCell(
        value: paymentInfoModel?.depositDeadline != null
            ? DateFormat('yyyy-MM-dd')
                .format(paymentInfoModel!.depositDeadline!)
            : (paymentInfoModel?.depositAmount != null &&
                    paymentInfoModel!.depositAmount! > 0
                ? OrdersStrings.gridDepositOnSiteLabel
                : ""),
      ),
      EshopColumnIds.ORDER_CREATED_AT: TrinaCell(
          value: createdAt != null
              ? DateFormat('yyyy-MM-dd').format(createdAt!)
              : ""),
      EshopColumnIds.ORDER_DATA: TrinaCell(value: toCustomerData()),
      EshopColumnIds.ORDER_EMAIL:
          TrinaCell(value: data?[TbEshop.orders.data_email] ?? ""),
      EshopColumnIds.TICKET_PRODUCTS: TrinaCell(
          value: relatedProducts != null
              ? relatedProducts!.map((p) => p.toBasicString()).join(" | ")
              : ""),
      EshopColumnIds.ORDER_DATA_NOTE: TrinaCell(value: toCustomerNote()),
      EshopColumnIds.ORDER_NOTE_HIDDEN: TrinaCell(value: noteHidden ?? ""),
      EshopColumnIds.ORDER_EMAIL_DELIVERY: TrinaCell(value: emailDelivery),
      EshopColumnIds.ORDER_OVERVIEW: TrinaCell(value: ""),
      EshopColumnIds.ORDER_HISTORY: TrinaCell(value: ""),
      EshopColumnIds.ORDER_TRANSACTIONS: TrinaCell(value: ""),
      EshopColumnIds.ORDER_FORM:
          TrinaCell(value: form?.definition.toString() ?? ""),
      EshopColumnIds.PAYMENT_INFO_REMINDER_SENT:
          TrinaCell(value: paymentInfoModel?.isReminderSent.toString() ?? ''),
      EshopColumnIds.ORDER_CONTRACT_DOWNLOAD: TrinaCell(value: ""),
      EshopColumnIds.ORDER_MODEL_REFERENCE: TrinaCell(value: this),
    });
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbOrders.deleteOrder(this);
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbOrders.updateOrderNoteHidden(id!, noteHidden!);
  }

  @override
  String toBasicString() {
    final symbol = orderSymbol?.trim() ?? '';
    final customer = toCustomerData().trim();
    final email = (data?['email'] as String?)?.trim() ?? '';
    return [
      if (symbol.isNotEmpty) symbol else if (id != null) '#$id',
      if (customer.isNotEmpty) customer,
      if (email.isNotEmpty && email != customer) email,
    ].join(' - ');
  }

  String toCustomerData() {
    final name = data?['name'] as String?;
    final surname = data?['surname'] as String?;

    bool hasName = name != null && name.isNotEmpty;
    bool hasSurname = surname != null && surname.isNotEmpty;

    if (hasName || hasSurname) {
      List<String> nameParts = [];
      if (hasName) {
        nameParts.add(name);
      }
      if (hasSurname) {
        nameParts.add(surname);
      }
      return nameParts.join(" ");
    } else {
      final email = data?['email'] as String?;
      bool hasEmail = email != null && email.isNotEmpty;

      if (hasEmail) {
        return email;
      }
    }

    return "";
  }

  String toCustomerNote() => "${data?["note"] ?? ""}";
  String toCustomerNoteHidden() => "${data?["note_hidden"] ?? ""}";
}
