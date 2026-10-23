import 'package:fstapp/components/blueprint/blueprint_seat_swap_preview.dart';
import 'package:fstapp/components/blueprint/blueprint_hold_release_preview.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:fstapp/components/blueprint/blueprint_object_model.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app_config.dart';

enum PasswordResetFailure { privilegedTarget }

class PasswordResetResult {
  final String? email;
  final PasswordResetFailure? failure;

  const PasswordResetResult({this.email, this.failure});

  factory PasswordResetResult.fromRpcResponse(dynamic response) {
    if (response is Map && response['code'] == 200) {
      return PasswordResetResult(email: response['email']?.toString());
    }

    if (response is Map &&
        response['code'] == 403 &&
        response['message'] ==
            'Security Restriction: Cannot reset password for privileged users via scan.') {
      return const PasswordResetResult(
        failure: PasswordResetFailure.privilegedTarget,
      );
    }

    return const PasswordResetResult();
  }
}

class DbTickets {
  static final _supabase = Supabase.instance.client;
  static TicketCommands get _commands => SupabaseTicketCommands(_supabase);

  static Future<BlueprintHoldReleasePreview> previewBlueprintHolds(
          int occasionId, List<int> spotIds) =>
      _commands.previewHoldRelease(spotIds,
          occasionId: occasionId,
          organizationId: AppConfig.organization,
          unitId: RightsService.currentUnit()?.id);

  static Future<void> releaseBlueprintHolds(
          BlueprintHoldReleasePreview preview) =>
      _commands.releaseHolds(preview);

  /// One canonical mutation for the complete selection, including email outcomes.
  static Future<TicketCancellationOutcome> stornoTickets(
      List<int> ticketIds) async {
    if (ticketIds.isEmpty) return const TicketCancellationOutcome();
    return _commands.cancel(ticketIds);
  }

  static Future<List<TicketModel>> getAllTickets(String occasionLink) async {
    var ordersBundle = await DbOrders.getAllOrdersBundle(
        occasionLink: occasionLink,
        includeOrderDetails: true,
        includeSpots: true);
    return ticketsFromOrdersBundle(ordersBundle);
  }

  /// Assemble the same ticket rows returned by the orders RPC for the ticket grid.
  static List<TicketModel> ticketsFromOrdersBundle(
      ReservationsBundle ordersBundle) {
    List<TicketModel> toReturn = [];
    for (var o in ordersBundle.orders) {
      for (TicketModel t in o.relatedTickets ?? []) {
        final snapshots = o.data?[TbEshop.tickets.table] as List? ?? const [];
        final snapshot = snapshots
            .whereType<Map>()
            .firstWhereOrNull((entry) => entry[TbEshop.tickets.id] == t.id);
        // Waiting and withdrawn tickets have no purchased-product snapshot.
        // Symbols can be NULL, so they cannot identify a ticket's price.
        t.totalPrice = snapshot == null
            ? null
            : (snapshot[TbEshop.products.table] as List? ?? const [])
                .fold<double>(
                    0,
                    (sum, product) =>
                        sum +
                        ((product[TbEshop.products.price] as num?)
                                ?.toDouble() ??
                            0));
      }
      toReturn.addAll(o.relatedTickets ?? []);
    }
    toReturn = toReturn.sortedBy((ou) => ou.createdAt!).reversed.toList();
    return toReturn;
  }

  static Future<FunctionResponse> sendTicketsToEmail({
    required int orderId,
    required String email,
    String? requestId,
    bool firstDelivery = false,
  }) async {
    final body = {
      "orderId": orderId,
      "email": email,
      "requestId": requestId ?? const Uuid().v4(),
      if (firstDelivery) "firstDelivery": true,
    };

    try {
      final response = await _supabase.functions.invoke(
        "send-tickets",
        body: body,
      );

      return response;
    } catch (e) {
      // Unexpected error in sendTicketsToEmail
      rethrow;
    }
  }

  /// Downloads the PDF for a specific ticket.
  static Future<Uint8List?> downloadTicketPdf(int ticketId) async {
    try {
      // Updated function name to 'download-ticket'
      final response = await _supabase.functions.invoke(
        "download-ticket",
        body: {"ticketId": ticketId},
      );

      final String? base64Str = response.data['file'];

      if (base64Str != null) {
        return base64Decode(base64Str);
      }
      return null;
    } catch (e) {
      // Error downloading ticket PDF
      rethrow;
    }
  }

  static Future<void> updateTicketNoteHidden(
      int ticketId, String newNoteHidden) async {
    var response = await _supabase.rpc(
      "update_ticket_note_hidden",
      params: {
        "ticket_id": ticketId,
        "new_note_hidden": newNoteHidden,
      },
    );
    if (response["code"] != 200) {
      throw Exception("Saving of note has failed.");
    }
  }

  static Future<List<Map<String, dynamic>>> getOrderHistory(int orderId) async {
    final response = await _supabase.rpc('get_order_history', params: {
      'order_id': orderId,
    });

    if (response["code"] != 200) {
      throw Exception("Failed to fetch order history: ${response['message']}");
    }

    var data = response["data"];

    // Directly return the list of items without grouping by date
    return List<Map<String, dynamic>>.from(data);
  }

  static Future<TicketModel?> scanTicket(
      String scannedId, String scannedCode) async {
    final response = await _supabase.rpc('scan_ticket', params: {
      'scanned_id': scannedId,
      'scanned_code': scannedCode,
    });

    if (response["code"] != 200) {
      return null;
    }

    // 1. Parse the returned ticket JSON data.
    final ticketJson = response["ticket"] as Map<String, dynamic>;
    TicketModel ticket = TicketModel.fromJson(ticketJson);

    // 2. Attach related order
    if (response.containsKey("order") && response["order"] != null) {
      ticket.relatedOrder = OrderModel.fromJson(response["order"]);
    }

    // 3. Attach related products
    if (response.containsKey("products") && response["products"] != null) {
      ticket.relatedProducts = (response["products"] as List)
          .map((p) => ProductModel.fromJson(p))
          .toList();
    }

    // 4. Attach related spot
    if (response.containsKey("spot") && response["spot"] != null) {
      ticket.relatedSpot = BlueprintObjectModel.fromJson(response["spot"]);
    }

    // 5. Attach related groups (NEW)
    if (response.containsKey("groups") && response["groups"] != null) {
      ticket.relatedGroups = (response["groups"] as List)
          .map((g) => UserGroupInfoModel.fromJson(g))
          .toList();
    }

    // 6. Attach deposit info from scan response
    if (response.containsKey("deposit_info") &&
        response["deposit_info"] != null) {
      ticket.depositInfo = response["deposit_info"] as Map<String, dynamic>;
    }

    return ticket;
  }

  static Future<void> useTicket(int ticketId) async {
    await _supabase.rpc(
      'update_ticket_to_used_ws',
      params: {
        'ticket_id': ticketId,
      },
    );
  }

  static Future<void> unuseTicket(int ticketId) async {
    await _supabase.rpc(
      'update_ticket_to_unused_ws',
      params: {
        'ticket_id': ticketId,
      },
    );
  }

  static Future<void> updateScanCode(
      String occasionLink, String scannedCode) async {
    final response = await _supabase.rpc('update_scan_code', params: {
      'occasion_link': occasionLink,
      'new_scan_code': scannedCode,
    });

    if (response["code"] != 200) {
      throw Exception("Error retrieving ticket: ${response["message"]}");
    }
  }

  static Future<bool> updateTicketToUsed(
      int ticketId, String scannedCode) async {
    final response = await _supabase.rpc('update_ticket_to_used', params: {
      'ticket_id': ticketId,
      'scan_code': scannedCode,
    });

    return response["code"] == 200;
  }

  static Future<String?> getScanCode(String occasionLink) async {
    final response = await _supabase.rpc('get_scan_code', params: {
      'occasion_link': occasionLink,
    });

    if (response["code"] != 200) {
      return null;
    }
    return response["scan_code"];
  }

  /// Resets the password for the user associated with the ticket.
  /// Returns the user's email on success or the RPC failure reason.
  static Future<PasswordResetResult> resetPassword(
      int ticketId, String password, String scannedCode) async {
    try {
      final response = await _supabase.rpc('reset_password_via_scan', params: {
        'ticket_id': ticketId,
        'password': password,
        'scan_code': scannedCode,
      });

      final result = PasswordResetResult.fromRpcResponse(response);
      if (result.email != null) {
        return PasswordResetResult(
          email: AppConfig.removeUserPrefix(result.email!),
        );
      }
      return result;
    } catch (e) {
      return const PasswordResetResult();
    }
  }

  static Future<BlueprintSeatSwapPreview> previewBlueprintSwap(
          {required int occasionId,
          required int blueprintId,
          required int firstSpotId,
          required int secondSpotId}) =>
      _commands.previewSwap(
          occasionId: occasionId,
          organizationId: AppConfig.organization,
          unitId: RightsService.currentUnit()?.id,
          blueprintId: blueprintId,
          firstSpotId: firstSpotId,
          secondSpotId: secondSpotId);

  static Future<bool> recoverBlueprintSwap(
          {required int occasionId, required int blueprintId}) =>
      _commands.recoverSwap(
          occasionId: occasionId,
          organizationId: AppConfig.organization,
          unitId: RightsService.currentUnit()?.id,
          blueprintId: blueprintId);

  static Future<void> swapBlueprintSpots(BlueprintSeatSwapPreview preview) =>
      _commands.swapSpots(preview);

  static Future<Map<String, dynamic>?> getOccasionByScanCode(
      String scanCode) async {
    try {
      final response =
          await _supabase.rpc('get_occasion_by_scan_code', params: {
        'scan_code': scanCode,
      });
      return response;
    } catch (e) {
      return null;
    }
  }

  static Future<List<TicketModel>> getAllTicketsForScan(String scanCode) async {
    final response = await _supabase.rpc(
      "get_all_tickets_for_scan",
      params: {"scan_code": scanCode},
    );

    if (response is List) {
      return response.map((json) {
        final ticket = TicketModel.fromJson(json);
        if (json.containsKey('related_order')) {
          ticket.relatedOrder = OrderModel.fromJson(json['related_order']);
        }
        return ticket;
      }).toList();
    }

    return [];
  }
}
