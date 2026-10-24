import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SavedProgramMode { join, remove, replace }

abstract interface class SavedProgramCommands {
  Future<List<int>> update(List<int> eventIds, SavedProgramMode mode);
}

class SupabaseSavedProgramCommands implements SavedProgramCommands {
  SupabaseSavedProgramCommands(SupabaseClient client, this._occasionId)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseSavedProgramCommands.withTransport(
    this._transport,
    this._occasionId,
  );

  final ClientCommandTransport _transport;
  final int _occasionId;

  @override
  Future<List<int>> update(List<int> eventIds, SavedProgramMode mode) async {
    final contextToken = ClientSyncRuntime.mutationContextToken;
    final raw = await _transport.invoke('set_saved_program_client_sync_v1', {
      'p_occasion': _occasionId,
      'p_event_ids': eventIds.toSet().toList()..sort(),
      'p_mode': mode.name,
    });
    if (!ClientSyncRuntime.isCurrentMutationContext(contextToken)) {
      throw StateError('Saved-program identity changed during mutation');
    }
    final response = ClientCommandResponse.from(raw);
    // EventPage owns this tiny optimistic state transition. Activating the
    // authoritative cache replacements must not bump the process-wide
    // projection epoch: OccasionHomePage keys its routed child by that epoch,
    // which would otherwise dispose and recreate the entire event detail.
    await applyClientCommandReplacements(
      response,
      notifyProjection: false,
      expectedContextToken: contextToken,
    );
    if (!ClientSyncRuntime.isCurrentMutationContext(contextToken)) {
      throw StateError('Saved-program identity changed during mutation');
    }
    final data = response.data;
    final saved = ((data['saved'] as List?) ?? const [])
        .whereType<num>()
        .map((id) => id.toInt())
        .toList(growable: false);
    final replacedPrivateProgram = response.replacements.any((replacement) =>
        replacement['component'] ==
        ClientSyncComponent.privateProgram.wireName);
    if (!replacedPrivateProgram) {
      await ClientSyncRuntime.refresh(
        SyncReason.manual,
        privateConsumer: true,
      );
    }
    return saved;
  }
}
