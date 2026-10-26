import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SpotCommands {
  Future<void> updateAssignments(List<Map<String, dynamic>> changes);
}

class SupabaseSpotCommands implements SpotCommands {
  SupabaseSpotCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseSpotCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<void> updateAssignments(List<Map<String, dynamic>> changes) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'update_spot_assignments_client_sync_v1',
      {'p_changes': changes},
    ));
    if (response.code != 200) {
      throw StateError('Spot assignment update was rejected');
    }
    await applyClientCommandReplacements(response);
  }
}
