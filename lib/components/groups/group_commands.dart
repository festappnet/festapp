import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum GroupCommandStatus { applied, unchanged, rejected, conflict }

class GroupCommandResult {
  const GroupCommandResult({
    required this.status,
    required this.version,
    this.group,
  });

  final GroupCommandStatus status;
  final int version;
  final UserGroupInfoModel? group;
}

abstract interface class GroupCommands {
  Future<GroupCommandResult> addMembers(
      int occasionId, int groupId, List<String> userIds);
  Future<GroupCommandResult> save(int occasionId, UserGroupInfoModel group);
  Future<GroupCommandResult> delete(int occasionId, UserGroupInfoModel group);
  Future<GroupCommandResult> replaceAssignments(
    int occasionId,
    Map<String, String?> groupTitleByUserId,
  );
}

class SupabaseGroupCommands implements GroupCommands {
  SupabaseGroupCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client, durable: true);

  SupabaseGroupCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<GroupCommandResult> addMembers(
      int occasionId, int groupId, List<String> userIds) async {
    final selected = userIds.toSet().toList()..sort();
    return _decode(await _invoke('add_user_group_members_client_sync_v1', {
      'p_occasion': occasionId,
      'p_group': groupId,
      'p_users': selected,
    }));
  }

  @override
  Future<GroupCommandResult> replaceAssignments(
    int occasionId,
    Map<String, String?> groupTitleByUserId,
  ) async {
    final response = await _invoke('replace_group_assignments_client_sync_v1', {
      'p_occasion': occasionId,
      'p_assignments': [
        for (final entry in groupTitleByUserId.entries)
          {'user_id': entry.key, 'group_title': entry.value},
      ],
    });
    return _decode(response);
  }

  @override
  Future<GroupCommandResult> save(
      int occasionId, UserGroupInfoModel group) async {
    final privatePlace =
        group.place?.isPrivateGroupLocation == true ? group.place : null;
    final response = await _invoke('save_user_group_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': group.id == null ? null : group.aggregateVersion,
      'p_group': {
        if (group.id case final id?) 'id': id,
        'title': group.title,
        'description': group.description,
        'type': group.type,
        'placeId': privatePlace == null ? group.place?.id : null,
        'privatePlace': privatePlace == null
            ? null
            : {
                if (privatePlace.id case final id?) 'id': id,
                'title': privatePlace.title,
                'description': privatePlace.description,
                'coordinates': {
                  'latLng': privatePlace.latLng,
                },
                'order': privatePlace.order,
                'icon': privatePlace.icon,
              },
        'participants': [
          for (final participant in group.participants ?? const {})
            {
              'user_id': participant.userInfo?.id,
              'is_admin': participant.isAdmin ?? false,
            },
        ],
      },
    });
    return _decode(response);
  }

  @override
  Future<GroupCommandResult> delete(
      int occasionId, UserGroupInfoModel group) async {
    final id = group.id;
    if (id == null) throw ArgumentError('Deleting a group requires its ID');
    return _decode(await _invoke('delete_user_group_client_sync_v1', {
      'p_occasion': occasionId,
      'p_group_id': id,
      'p_expected_version': group.aggregateVersion,
    }));
  }

  Future<ClientCommandResponse> _invoke(
      String name, Map<String, dynamic> parameters) async {
    final response =
        ClientCommandResponse.from(await _transport.invoke(name, parameters));
    await applyClientCommandReplacements(response);
    return response;
  }

  GroupCommandResult _decode(ClientCommandResponse response) {
    final version = (response.data['version'] as num?)?.toInt() ?? 0;
    final raw = response.data['group'];
    return GroupCommandResult(
      status: GroupCommandStatus.values.byName(response.status),
      version: version,
      group: raw is Map
          ? UserGroupInfoModel.fromJson({
              ...raw.cast<String, dynamic>(),
              'aggregate_version': version,
            })
          : null,
    );
  }
}
