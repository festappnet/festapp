import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

bool validTicketBatchEmail(String value) =>
    value.isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

/// Batch commands own transaction intent. Views never orchestrate order/payment RPCs.
abstract interface class TicketBatchCommands {
  Future<Map<String, dynamic>> create(
      {required int formId,
      required String title,
      required List<Map<String, dynamic>> selection,
      String? spotSecret});
  Future<Map<String, dynamic>> sell(
      {required String batchId,
      required List<int> ticketIds,
      Map<String, String> contact = const {},
      bool sendTickets = false});
  Future<Map<String, dynamic>?> recoverPendingSale(String batchId);
  Future<void> voidItems(String batchId, List<int> ticketIds, String reason);
}

class SupabaseTicketBatchCommands implements TicketBatchCommands {
  SupabaseTicketBatchCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client,
            durable: true, retrySerialization: true);
  SupabaseTicketBatchCommands.withTransport(this._transport);
  final ClientCommandTransport _transport;

  Future<Map<String, dynamic>> _run(
      String rpc, Map<String, dynamic> params) async {
    final result =
        ClientCommandResponse.from(await _transport.invoke(rpc, params));
    if (result.code != 200) {
      throw StateError(result.data['errorCode']?.toString() ??
          'Ticket batch command rejected');
    }
    await applyClientCommandReplacements(result);
    return result.data;
  }

  @override
  Future<Map<String, dynamic>> create(
      {required int formId,
      required String title,
      required List<Map<String, dynamic>> selection,
      String? spotSecret}) async {
    final name = title.trim();
    if (formId <= 0 ||
        name.isEmpty ||
        name.runes.length > 200 ||
        selection.isEmpty ||
        selection.length > 200) {
      throw ArgumentError('Invalid ticket batch input');
    }
    return _run('create_ticket_batch_client_sync_v1', {
      'p_form': formId,
      'p_title': name,
      'p_selection': selection,
      'p_secret': spotSecret
    });
  }

  @override
  Future<Map<String, dynamic>> sell(
      {required String batchId,
      required List<int> ticketIds,
      Map<String, String> contact = const {},
      bool sendTickets = false}) async {
    final email = contact['email']?.trim() ?? '';
    if (!validTicketBatchEmail(email) || (sendTickets && email.isEmpty)) {
      throw ArgumentError('Invalid delivery email');
    }
    final ids = ticketIds.toSet().toList()..sort();
    if (ids.isEmpty || ids.length > 20) {
      throw ArgumentError('Select 1-20 tickets');
    }
    return _run('sell_ticket_batch_items_client_sync_v1', {
      'p_batch': batchId,
      'p_tickets': ids,
      'p_contact': contact,
      'p_send_tickets': sendTickets
    });
  }

  @override
  Future<Map<String, dynamic>?> recoverPendingSale(String batchId) async {
    final intent = await _transport.pendingIntent(
        'sell_ticket_batch_items_client_sync_v1', {'p_batch': batchId});
    if (intent == null) return null;
    final result = ClientCommandResponse.from(await _transport.resume(intent));
    if (result.code != 200) throw StateError('Ticket batch recovery rejected');
    await applyClientCommandReplacements(result);
    return result.data;
  }

  @override
  Future<void> voidItems(
      String batchId, List<int> ticketIds, String reason) async {
    final ids = ticketIds.toSet().toList()..sort();
    await _run('void_ticket_batch_items_client_sync_v1',
        {'p_batch': batchId, 'p_tickets': ids, 'p_reason': reason});
  }
}
