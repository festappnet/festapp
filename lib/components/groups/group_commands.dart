import 'dart:convert';
import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

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
  Future<GroupCommandResult> save(int occasionId, UserGroupInfoModel group);
  Future<GroupCommandResult> delete(int occasionId, UserGroupInfoModel group);
  Future<GroupCommandResult> replaceAssignments(
    int occasionId,
    Map<String, String?> groupTitleByUserId,
  );
}

class SupabaseGroupCommands implements GroupCommands {
  SupabaseGroupCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client),
        _actorId = (() => client.auth.currentUser?.id);

  SupabaseGroupCommands.withTransport(this._transport,
      {String? Function()? actorId})
      : _actorId = actorId ?? (() => null);

  final ClientCommandTransport _transport;
  final String? Function() _actorId;
  final _creations = Expando<_GroupCreationIntent>();

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
    if (group.participants == null) {
      throw StateError('Complete group membership must be loaded before save');
    }
    final privatePlace =
        group.place?.isPrivateGroupLocation == true ? group.place : null;
    final requested = <String, dynamic>{
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
    };
    final actor = _actorId();
    final context = ClientSyncRuntime.mutationContextToken;
    var creation = _creations[group];
    if (creation != null &&
        (creation.actor != actor || creation.context != context)) {
      throw StateError('Reload the group editor after identity change');
    }
    if (group.id == null) {
      creation ??= _GroupCreationIntent(
          jsonDecode(jsonEncode(requested)) as Map<String, dynamic>,
          privatePlace,
          actor,
          context);
      _creations[group] = creation;
    }
    ClientCommandResponse response;
    try {
      response = await _invoke(
          'save_user_group_client_sync_v1', creation?.parameters ?? requested,
          intentKey: creation?.key);
    } on PostgrestException catch (error) {
      // A first PostgreSQL error proves rollback. After an ambiguous attempt,
      // an authorization error cannot disprove that the earlier create committed.
      if (RegExp(r'^[A-Z0-9]{5}$').hasMatch(error.code ?? '') &&
          creation?.ambiguous != true) {
        _creations[group] = null;
      } else {
        creation?.ambiguous = true;
      }
      rethrow;
    } catch (_) {
      creation?.ambiguous = true;
      rethrow;
    }
    if (creation != null) {
      _creations[group] = null;
      final confirmed = _decode(response);
      if (confirmed.group != null &&
          (confirmed.status == GroupCommandStatus.applied ||
              confirmed.status == GroupCommandStatus.unchanged) &&
          actor == _actorId() &&
          ClientSyncRuntime.isCurrentMutationContext(context) &&
          ClientCommandIdentity.fingerprint(creation.parameters) !=
              ClientCommandIdentity.fingerprint(requested)) {
        group.acceptSavedIdentity(confirmed.group!, creation.place);
        requested['p_expected_version'] = confirmed.version;
        final dto = requested['p_group'] as Map;
        dto['id'] = confirmed.group!.id;
        if (identical(privatePlace, creation.place) &&
            dto['privatePlace'] is Map) {
          (dto['privatePlace'] as Map)['id'] = confirmed.group!.place?.id;
        }
        response = await _invoke('save_user_group_client_sync_v1', requested);
      }
    }
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
      String name, Map<String, dynamic> parameters,
      {String? intentKey}) async {
    final context = ClientSyncRuntime.mutationContextToken;
    final actor = _actorId();
    final response = ClientCommandResponse.from(await _transport.invokeIntent(
        '$actor:${parameters['p_occasion']}:$name:${intentKey ?? ''}',
        name,
        parameters));
    if (_actorId() == actor) {
      await response.applyConfirmedReplacements(expectedContextToken: context);
    }
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

class _GroupCreationIntent {
  _GroupCreationIntent(this.parameters, this.place, this.actor, this.context);
  bool ambiguous = false;
  final String key = ClientCommandIdentity.newCommandId();
  final Map<String, dynamic> parameters;
  final PlaceModel? place;
  final String? actor;
  final String context;
}
