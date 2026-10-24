import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CardRefundTicket {
  CardRefundTicket.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        label = json['label'] as String,
        state = json['state'] as String;
  final int id;
  final String label, state;
  bool get canCancel => const {'paid', 'sent', 'ordered'}.contains(state);
}

class CardRefundDetail {
  CardRefundDetail.fromJson(Map<String, dynamic> json)
      : orderId = json['orderId'] as int,
        refundedMinor = json['refundedMinor'] as int,
        amountMinor = json['amountMinor'] as int,
        currency = json['currency'] as String,
        canDecide = json['canDecide'] == true,
        reconciliationPending = json['reconciliationPending'] == true,
        decision = (json['decision'] as Map?)?.cast<String, dynamic>(),
        tickets = (json['tickets'] as List)
            .map((value) =>
                CardRefundTicket.fromJson(Map<String, dynamic>.from(value)))
            .toList(),
        dashboardUrl = json['dashboardUrl'] as String?;
  final int orderId, refundedMinor, amountMinor;
  final String currency;
  final bool canDecide, reconciliationPending;
  final Map<String, dynamic>? decision;
  final List<CardRefundTicket> tickets;
  final String? dashboardUrl;

  Uri? get dashboardUri {
    final uri = Uri.tryParse(dashboardUrl ?? '');
    return uri != null &&
            uri.scheme == 'https' &&
            uri.host == 'dashboard.stripe.com' &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }
}

abstract interface class CardRefundDecisionApi {
  Future<CardRefundDetail?> read(int orderId);
  Future<void> decide(
      {required CardRefundDetail detail,
      required String action,
      required List<int> ticketIds,
      required String note});
}

class SupabaseCardRefundDecisionApi implements CardRefundDecisionApi {
  SupabaseCardRefundDecisionApi() : _client = Supabase.instance.client;
  final SupabaseClient _client;
  @override
  Future<CardRefundDetail?> read(int orderId) async {
    final response = await _client
        .rpc('get_stripe_order_admin_detail', params: {'p_order': orderId});
    return response == null
        ? null
        : CardRefundDetail.fromJson(Map<String, dynamic>.from(response));
  }

  @override
  Future<void> decide(
      {required CardRefundDetail detail,
      required String action,
      required List<int> ticketIds,
      required String note}) async {
    final ids = ticketIds.toSet().toList()..sort();
    final response = ClientCommandResponse.from(
        await ClientCommandTransport.supabase(_client, durable: true)
            .invoke('decide_stripe_partial_refund_client_sync_v1', {
      'p_order': detail.orderId,
      'p_action': action,
      'p_tickets': ids,
      'p_note': note.trim(),
      'p_expected_refunded_minor': detail.refundedMinor,
    }));
    if (response.code != 200) {
      throw StateError('STRIPE_REFUND_DECISION_INVALID');
    }
    await applyClientCommandReplacements(response);
  }
}
