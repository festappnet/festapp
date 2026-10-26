import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ParticipantCompanionCommands {
  Future<CompanionModel> createSelf(int occasionId, String name);
  Future<void> deleteSelf(int occasionId, String companionId);
}

abstract interface class AdminCompanionCommands {
  Future<void> assignExisting(
      int occasionId, String ownerId, String companionId);
  Future<void> unassignExisting(
      int occasionId, String ownerId, String companionId);
}

class SupabaseCompanionCommands
    implements ParticipantCompanionCommands, AdminCompanionCommands {
  SupabaseCompanionCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseCompanionCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<CompanionModel> createSelf(int occasionId, String name) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'create_companion_client_sync_v1',
      {'p_occasion': occasionId, 'p_name': name},
    ));
    await applyClientCommandReplacements(response);
    final raw = response.data['companion'];
    if (response.code != 200 || response.status != 'applied' || raw is! Map) {
      throw StateError('Companion create was rejected');
    }
    return CompanionModel.fromJson(raw.cast<String, dynamic>());
  }

  @override
  Future<void> deleteSelf(int occasionId, String companionId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_owned_companion_client_sync_v1',
      {'p_occasion': occasionId, 'p_companion': companionId},
    ));
    await applyClientCommandReplacements(response);
    if (response.code != 200 ||
        (response.status != 'applied' && response.status != 'unchanged')) {
      throw StateError('Companion delete was rejected');
    }
  }

  Future<void> _adminCommand(
      String name, int occasionId, String ownerId, String companionId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(name, {
      'p_occasion': occasionId,
      'p_owner': ownerId,
      'p_companion': companionId,
    }));
    if (response.code != 200 ||
        (response.status != 'applied' && response.status != 'unchanged')) {
      throw StateError('Companion assignment was rejected');
    }
  }

  @override
  Future<void> assignExisting(
          int occasionId, String ownerId, String companionId) =>
      _adminCommand('assign_existing_companion_client_sync_v1', occasionId,
          ownerId, companionId);

  @override
  Future<void> unassignExisting(
          int occasionId, String ownerId, String companionId) =>
      _adminCommand('unassign_existing_companion_client_sync_v1', occasionId,
          ownerId, companionId);
}
