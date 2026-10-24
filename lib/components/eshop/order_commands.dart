import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class OrderCommands {
  Future<Map<String, dynamic>> repairEmail(
      {required int orderId,
      required String expectedEmail,
      required String expectedState,
      required int expectedPaymentVersion,
      required String expectedPaymentFingerprint,
      required String email,
      String? sourceMessageId,
      required bool resend,
      String? commandId});
  Future<void> delete(int orderId, {String? commandId});
  Future<void> cancel(int orderId, {String? commandId});
}

class SupabaseOrderCommands implements OrderCommands {
  SupabaseOrderCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client, durable: true);

  SupabaseOrderCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<Map<String, dynamic>> repairEmail(
      {required int orderId,
      required String expectedEmail,
      required String expectedState,
      required int expectedPaymentVersion,
      required String expectedPaymentFingerprint,
      required String email,
      String? sourceMessageId,
      required bool resend,
      String? commandId}) async {
    final parameters = <String, dynamic>{
      'p_order': orderId,
      'p_expected_email': expectedEmail,
      'p_expected_state': expectedState,
      'p_expected_payment_version': expectedPaymentVersion,
      'p_expected_payment_fingerprint': expectedPaymentFingerprint,
      'p_email': email,
      'p_source_message': sourceMessageId,
      'p_resend': resend,
      if (commandId != null) 'p_command_id': commandId,
    };
    final raw = commandId == null
        ? await _transport.invokeIntent('inventory.order.repair_email',
            'repair_order_email_client_sync_v1', parameters)
        : await _transport.invoke(
            'repair_order_email_client_sync_v1', parameters);
    final response = ClientCommandResponse.from(raw);
    if (response.code != 200 && response.code != 409) {
      throw StateError('Order email repair was rejected');
    }
    if (response.code == 200) await applyClientCommandReplacements(response);
    return Map<String, dynamic>.from(raw as Map);
  }

  @override
  Future<void> cancel(int orderId, {String? commandId}) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'storno_order_client_sync_v1',
      {'p_order': orderId, if (commandId != null) 'p_command_id': commandId},
    ));
    if (response.code != 200) {
      throw StateError('Order cancellation was rejected');
    }
    await applyClientCommandReplacements(response);
  }

  @override
  Future<void> delete(int orderId, {String? commandId}) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_order_client_sync_v1',
      {'p_order': orderId, if (commandId != null) 'p_command_id': commandId},
    ));
    if (response.code != 200) {
      throw StateError('Order deletion was rejected');
    }
    await applyClientCommandReplacements(response);
  }
}
