import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class OrderCommands {
  Future<void> delete(int orderId, {String? commandId});
  Future<void> cancel(int orderId, {String? commandId});
}

class SupabaseOrderCommands implements OrderCommands {
  SupabaseOrderCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseOrderCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

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
