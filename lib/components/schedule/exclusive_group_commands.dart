import 'package:fstapp/components/schedule/exclusive_group_model.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class ExclusiveGroupCommands {
  Future<List<ExclusiveGroupModel>> list(int occasionId);
  Future<ExclusiveGroupModel> save(int occasionId, ExclusiveGroupModel group);
  Future<void> delete(int occasionId, ExclusiveGroupModel group);
}

class SupabaseExclusiveGroupCommands implements ExclusiveGroupCommands {
  SupabaseExclusiveGroupCommands(SupabaseClient client)
      : _client = client,
        _transport = ClientCommandTransport.supabase(client);

  SupabaseExclusiveGroupCommands.withTransport(this._client, this._transport);

  final SupabaseClient? _client;
  final ClientCommandTransport _transport;

  @override
  Future<List<ExclusiveGroupModel>> list(int occasionId) async {
    final raw = await _client!.rpc(
      'get_exclusive_groups_for_edit_v1',
      params: {'p_occasion': occasionId},
    );
    return (raw as List)
        .map((row) => ExclusiveGroupModel.fromJson(
              (row as Map).cast<String, dynamic>(),
            ))
        .toList();
  }

  @override
  Future<ExclusiveGroupModel> save(
    int occasionId,
    ExclusiveGroupModel group,
  ) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'save_exclusive_group_client_sync_v1',
      {
        'p_occasion': occasionId,
        'p_expected_version': group.id == null ? null : group.aggregateVersion,
        'p_group': {
          if (group.id != null) 'id': group.id,
          'title': group.title,
          'events': group.events ?? <int>[],
        },
      },
    ));
    if (response.status == 'conflict') {
      throw StateError('Exclusive group was changed by another editor');
    }
    final raw = response.data['group'];
    if (response.code != 200 || raw is! Map) {
      throw StateError('Exclusive group save was rejected');
    }
    return ExclusiveGroupModel.fromJson(raw.cast<String, dynamic>());
  }

  @override
  Future<void> delete(int occasionId, ExclusiveGroupModel group) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'delete_exclusive_group_client_sync_v1',
      {
        'p_occasion': occasionId,
        'p_group_id': group.id,
        'p_expected_version': group.aggregateVersion,
      },
    ));
    if (response.status == 'conflict') {
      throw StateError('Exclusive group was changed by another editor');
    }
    if (response.code != 200 ||
        (response.status != 'applied' && response.status != 'unchanged')) {
      throw StateError('Exclusive group delete was rejected');
    }
  }
}
