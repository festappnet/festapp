import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class WaitlistCommandException implements Exception {
  WaitlistCommandException(this.data);
  final Map<String, dynamic> data;
  @override
  String toString() =>
      data['errorCode']?.toString() ?? 'WAITLIST_COMMAND_FAILED';
}

/// In-memory command identities: capability data must never be persisted.
class WaitlistCommands {
  WaitlistCommands([SupabaseClient? client])
      : client = client ?? Supabase.instance.client;
  final SupabaseClient client;
  final String _clientId = const Uuid().v4();
  final Map<String, String> _pending = {};

  Future<Map<String, dynamic>> read(
      {String? token, String? offerId, int? orderId}) async {
    final result = Map<String, dynamic>.from(
        await client.rpc('get_waitlist_offer_form', params: {
      'p_token': token,
      'p_offer_id': offerId,
      'p_order_id': orderId,
    }));
    if (result['code'] != 200) throw StateError('INVALID_CAPABILITY');
    return result;
  }

  Future<Map<String, dynamic>> preview(int formId) async =>
      Map<String, dynamic>.from(await client.rpc(
          'get_waitlist_offer_email_preview',
          params: {'p_form_id': formId}));
  Future<Map<String, dynamic>> proposal(int formId) async =>
      Map<String, dynamic>.from(await client
          .rpc('get_waitlist_offer_proposal', params: {'p_form_id': formId}));
  Future<Map<String, dynamic>> detail(int orderId) async =>
      Map<String, dynamic>.from(await client
          .rpc('get_waitlist_order_detail', params: {'p_order_id': orderId}));

  Future<Map<String, dynamic>> command(
          String operation, Map<String, dynamic> payload) =>
      _invoke(
          'waitlist-commands', {'operation': operation, 'payload': payload});
  Future<Map<String, dynamic>> accept(
          {required String offerId,
          String? token,
          required List<int> ticketIds,
          required Map<String, dynamic> orderDetails}) =>
      _invoke('send-ticket-order', {
        'waitlistAcceptance': {
          'offerId': offerId,
          if (token != null) 'token': token,
          'ticketIds': ticketIds
        },
        'orderDetails': orderDetails,
      });
  Future<Map<String, dynamic>> _invoke(
      String endpoint, Map<String, dynamic> body) async {
    final identity = '$endpoint:$body';
    final commandId = _pending.putIfAbsent(identity, () => const Uuid().v4());
    final transport = ClientCommandTransport((_, parameters) async {
      final response = await client.functions.invoke(endpoint,
          body: {...body, 'commandId': commandId, 'clientId': _clientId});
      return response.data;
    });
    final raw = await transport.invoke(endpoint, {});
    final response = ClientCommandResponse.from(raw);
    _pending.remove(identity);
    if (response.code != 200) throw WaitlistCommandException(response.data);
    await response.applyReplacements();
    return response.data;
  }
}
