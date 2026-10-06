import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';

import 'package:fstapp/components/blueprint/get_orders_helper.dart';
import 'package:fstapp/components/eshop/models/orders_history_model.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/order_commands.dart';
import 'package:fstapp/components/eshop/models/order_product_ticket_model.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/forms/models/form_response_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReservationsBundle {
  final List<OrderModel> orders;
  final List<FormModel> forms;

  ReservationsBundle({
    required this.orders,
    required this.forms,
  });
}

class OrderHistoryBundle {
  final OrderModel order;
  final List<OrderHistoryModel> history;
  OrderHistoryBundle({required this.order, required this.history});
}

class DbOrders {
  static final _supabase = Supabase.instance.client;
  static OrderCommands get _commands => SupabaseOrderCommands(_supabase);

  static Future<FunctionResponse> sendTicketOrder(
      Map<String, dynamic> data) async {
    return _sendTicketOrderIntent(
      namespace: 'ticket_order',
      payload: data,
      bodyKey: 'orderDetails',
    );
  }

  static Future<FunctionResponse> replaceTicketOrder(
    List<int> spotIds,
    Map<String, dynamic> inputData,
  ) async {
    final replacement = {
      'spotIds': spotIds,
      'inputData': inputData,
    };
    return _sendTicketOrderIntent(
      namespace: 'ticket_order_replace',
      payload: replacement,
      bodyKey: 'replacement',
    );
  }

  static Future<FunctionResponse> _sendTicketOrderIntent({
    required String namespace,
    required Map<String, dynamic> payload,
    required String bodyKey,
  }) async {
    final clientId = await ClientCommandIdentity.clientId();
    final commandId = await ClientCommandIdentity.claimIntent(
      namespace,
      payload,
    );
    final response = await _supabase.functions.invoke(
      "send-ticket-order",
      body: {
        bodyKey: payload,
        "commandId": commandId,
        "clientId": clientId,
      },
    );
    await ClientCommandIdentity.completeIntent(namespace, payload);
    return response;
  }

  static Future<void> stornoOrder(int id) async {
    if (ClientSyncRuntime.isV1Selected) {
      await _commands.cancel(id);
    } else {
      await _supabase.rpc(
        'update_order_and_tickets_to_storno_ws_221',
        params: {'order_id': id},
      );
    }

    await sendStornoTicketOrderEmail(orderId: id);
  }

  static Future<bool> selectSpot(BuildContext context, String formKey,
      String secret, int spotId, bool selecting) async {
    final response = await _supabase.rpc(
      'select_spot',
      params: {
        'form_key': formKey,
        'secret_id': secret,
        'spot_id': spotId,
        'selecting': selecting,
      },
    );

    var code = response["code"];
    var message = response["message"];

    if (code != 200) {
      ToastHelper.Show(context, message.toString(),
          severity: ToastSeverity.NotOk);
      return false;
    }
    return true;
  }

  static Future<ReservationsBundle> getAllOrdersBundle({
    String? occasionLink,
    String? formLink,
    bool includeOrderDetails = false,
    bool includeSpots = false,
    bool includeOrdersHistory = false,
  }) async {
    assert(occasionLink != null || formLink != null,
        'Either occasionLink or formLink must be provided.');

    final options = <String, bool>{};
    if (includeOrderDetails) options['include_full_order_data'] = true;
    if (includeSpots) options['include_spots'] = true;
    if (includeOrdersHistory) options['include_orders_history'] = true;

    final params = <String, dynamic>{
      'p_occasion_link': occasionLink,
      'p_form_link': formLink,
      if (options.isNotEmpty) 'p_options': options,
    };

    final response = await _supabase.rpc('get_orders', params: params);

    if (response["code"] != 200) {
      throw Exception("${response['code']}: ${response['message']}");
    }

    return _parseOrdersBundle(response["data"]);
  }

  static Future<ReservationsBundle> getOrdersTabData({
    required String occasionLink,
  }) async {
    final response = await _supabase.rpc('get_orders_tab_data', params: {
      'p_occasion_link': occasionLink,
    });

    // Response is the data object directly.
    return _parseOrdersBundle(response);
  }

  static ReservationsBundle _parseOrdersBundle(dynamic json) {
    // Basic data parsing
    final spots = GetOrdersHelper.parseSpots(json);
    final products = GetOrdersHelper.parseProducts(json);
    GetOrdersHelper.parseProductTypes(json);
    final tickets = GetOrdersHelper.parseTickets(json);
    final orders = GetOrdersHelper.parseOrders(json)!;
    if (orders.any((order) => order.orderSymbol == null)) {
      throw const FormatException('Missing order symbol in orders response');
    }
    final payments = GetOrdersHelper.parsePaymentInfo(json);
    final forms = GetOrdersHelper.parseForms(json);
    final orderProductTickets = GetOrdersHelper.parseOrderProductTickets(json);
    final ordersHistory = GetOrdersHelper.parseOrdersHistory(json);
    final users = GetOrdersHelper.parseUsers(json);

    // Create lookup maps for efficient linking
    final ticketMap = {for (var t in tickets!) t.id: t};
    final productMap = {for (var p in products!) p.id: p};
    final paymentMap = {for (var p in payments!) p.id: p};
    final spotByOptId = {for (var s in spots!) s.orderProductTicket: s};
    final userMap = {for (var u in users!) u.id: u};

    // Link users to history records
    if (ordersHistory != null) {
      for (final historyItem in ordersHistory) {
        historyItem.createdBy = userMap[historyItem.createdById];
      }
    }

    // Group history by order ID for efficient lookup
    final historyMap = groupBy(ordersHistory!, (h) => h.orderId);

    final Map<int, List<OrderProductTicketModel>> orderToOpt = {};
    final Map<int, List<OrderProductTicketModel>> ticketToOpt = {};
    for (var opt in orderProductTickets!) {
      orderToOpt.putIfAbsent(opt.orderId!, () => []).add(opt);
      ticketToOpt.putIfAbsent(opt.ticketId!, () => []).add(opt);
    }

    // Main loop to assemble the final OrderModel objects
    for (var order in orders) {
      final delivery = (json['email_delivery'] as Map?)?[order.id.toString()];
      order.emailDelivery =
          delivery is Map ? Map<String, dynamic>.from(delivery) : null;
      final orderOpts = orderToOpt[order.id] ?? [];
      final ticketIds = orderOpts.map((opt) => opt.ticketId).toSet();
      final relatedTickets = ticketIds
          .map((id) => ticketMap[id])
          .whereType<TicketModel>()
          .toList();

      order.relatedTickets = relatedTickets;
      order.form = forms?.firstWhereOrNull((f) => f.id == order.formId);
      if (order.form == null && order.formKey != null) {
        order.form = forms?.firstWhereOrNull((f) => f.key == order.formKey);
      }
      order.relatedHistory = historyMap[order.id];

      for (var ticket in relatedTickets) {
        final ticketOpts = ticketToOpt[ticket.id] ?? [];
        for (var opt in ticketOpts) {
          if (spotByOptId.containsKey(opt.id)) {
            ticket.relatedSpot = spotByOptId[opt.id];
            break;
          }
        }
        final productIds = ticketOpts.map((opt) => opt.productId).toSet();
        ticket.relatedProducts = productIds
            .map((pid) => productMap[pid])
            .whereType<ProductModel>()
            .toList();
        ticket.relatedOrder = order;
      }

      final ticketIdsForOrder = relatedTickets.map((t) => t.id).toSet();
      order.relatedSpots = spots
          .where((s) => ticketIdsForOrder.contains(s.orderProductTicket))
          .toList();

      final orderProductIds = <int>{};
      for (var ticket in relatedTickets) {
        if (ticket.relatedProducts != null) {
          orderProductIds.addAll(ticket.relatedProducts!.map((p) => p.id!));
        }
      }
      order.relatedProducts =
          products.where((p) => orderProductIds.contains(p.id)).toList();
      order.paymentInfoModel = paymentMap[order.paymentInfo];

      if (order.isExpired()) {
        order.state = OrderModel.expiredState;
        for (var t in order.relatedTickets!
            .where((t) => t.state == OrderModel.orderedState)) {
          t.state = order.state;
        }
      }
    }

    orders.sort((a, b) => b.createdAt!.compareTo(a.createdAt!));

    return ReservationsBundle(orders: orders, forms: forms ?? []);
  }

  static Future<void> deleteOrder(OrderModel model) async {
    if (ClientSyncRuntime.isV1Selected) {
      await _commands.delete(model.id!);
      return;
    }
    await _supabase.rpc(
      'delete_order_221',
      params: {
        'order_id': model.id,
      },
    );
  }

  static Future<void> updateOrderResponses(FormResponseModel responses) async {
    await _supabase.rpc(
      'update_order_responses',
      params: {'p_order_id': responses.id, 'responses': responses.fields},
    );
  }

  /// Deletes a specific order history record by its ID.
  /// Throws a [PostgrestException] if the deletion fails due to permissions or other issues.
  static Future<void> deleteOrderHistory(int historyId) async {
    await _supabase.rpc(
      'delete_order_history',
      params: {
        'p_history_id': historyId,
      },
    );
  }

  static Future<void> updateOrderNoteHidden(
      int orderId, String newNoteHidden) async {
    var response = await _supabase.rpc(
      "update_order_note_hidden",
      params: {
        "order_id": orderId,
        "new_note_hidden": newNoteHidden,
      },
    );
    if (response["code"] != 200) {
      throw Exception("Saving of note has failed.");
    }
  }

  static Future<void> updateOrderAndTicketsToPaid(int orderId) async {
    var response = await _supabase.rpc(
      "update_order_and_tickets_to_paid_ws",
      params: {
        "order_id": orderId,
      },
    );

    if (response["code"] != 200) {
      throw Exception(
          "Failed to update order and tickets to 'paid'. Error: ${response['message']}");
    }
  }

  static Future<OrderHistoryBundle> getOrderHistory(int orderId) async {
    final response = await _supabase.rpc('get_order_history', params: {
      'order_id': orderId,
    });

    if (response["code"] != 200) {
      throw Exception("Failed to fetch order history: ${response['message']}");
    }

    final json = response["data"];

    // Parse all parts from the new API response
    final order = OrderModel.fromJson(json['order']);
    final history = (json['history'] as List)
        .map((h) => OrderHistoryModel.fromJson(h))
        .toList();
    final users =
        (json['users'] as List).map((u) => UserInfoModel.fromJson(u)).toList();

    // Link users to history items
    final userMap = {for (var u in users) u.id: u};
    for (final historyItem in history) {
      historyItem.createdBy = userMap[historyItem.createdById];
    }

    // Set the parsed history on the order model
    order.relatedHistory = history;

    return OrderHistoryBundle(order: order, history: history);
  }

  static Future<FunctionResponse> sendStornoTicketOrderEmail({
    required int orderId,
  }) async {
    final body = {
      "code": "TICKET_ORDER_STORNO",
      "data": {"orderId": orderId},
    };

    try {
      final response = await _supabase.functions.invoke(
        "send-email",
        body: body,
      );

      return response;
    } catch (e) {
      // Unexpected error in sendTicketsToEmail
      rethrow;
    }
  }

  static Future<Uint8List?> downloadContractPdf(int orderId) async {
    try {
      final response = await _supabase.functions
          .invoke("generate-order-agreement", body: {"orderId": orderId});

      final String? base64Str = response.data['file'];

      if (base64Str != null) {
        return base64Decode(base64Str);
      }
      return null;
    } catch (e) {
      // Error downloading contract
      rethrow;
    }
  }

  static Future<void> insertManualTransaction({
    required double amount,
    required String currency,
    required int unitId,
    required String? variableSymbol,
    required DateTime date,
    String? note,
    int? paymentInfoId,
  }) async {
    final params = {
      'p_amount': amount,
      'p_currency': currency,
      'p_unit_id': unitId,
      'p_variable_symbol': variableSymbol,
      'p_date': date.toIso8601String(),
      'p_note': note,
      'p_payment_info_id': paymentInfoId,
    };

    try {
      await _supabase.rpc(
        'insert_manual_transaction',
        params: params,
      );
    } catch (e) {
      rethrow;
    }
  }
}
