import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

enum ProfileCommandStatus { applied, unchanged, rejected, conflict }

class ProfileCommandResult {
  const ProfileCommandResult({
    required this.status,
    required this.version,
    this.userId,
  });

  final ProfileCommandStatus status;
  final int version;
  final String? userId;
}

abstract interface class ProfileCommands {
  Future<ProfileCommandResult> save(OccasionUserModel profile);
  Future<ProfileCommandResult> create(OccasionUserModel profile);
  Future<ProfileCommandResult> delete(OccasionUserModel profile);
  Future<ProfileCommandResult> importProfiles(
    int occasionId,
    List<Map<String, dynamic>> rows,
    List<String> deleteUserIds,
  );
  Future<Map<String, dynamic>> importFromTickets(int occasionId);
  Future<void> ensureMembership(int occasionId, String userId);
}

class SupabaseProfileCommands implements ProfileCommands {
  SupabaseProfileCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client),
        _actorId = (() => client.auth.currentUser?.id);

  SupabaseProfileCommands.withTransport(this._transport)
      : _actorId = (() => null);

  final ClientCommandTransport _transport;
  final String? Function() _actorId;

  @override
  Future<void> ensureMembership(int occasionId, String userId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'add_user_to_occasion_client_sync_v1',
      {'p_occasion': occasionId, 'p_user': userId},
    ));
    if (response.code != 200) {
      throw StateError('Occasion membership was rejected');
    }
    await response.applyReplacements();
  }

  @override
  Future<Map<String, dynamic>> importFromTickets(int occasionId) async {
    final response = ClientCommandResponse.from(await _transport.invoke(
      'import_users_from_tickets_client_sync_v1',
      {'p_occasion': occasionId},
    ));
    await response.applyReplacements();
    return response.data;
  }

  @override
  Future<ProfileCommandResult> importProfiles(
    int occasionId,
    List<Map<String, dynamic>> rows,
    List<String> deleteUserIds,
  ) =>
      _invoke('import_profiles_client_sync_v1', {
        'p_occasion': occasionId,
        'p_rows': rows,
        'p_delete_user_ids': deleteUserIds,
      });

  @override
  Future<ProfileCommandResult> delete(OccasionUserModel profile) async {
    final occasion = profile.occasion;
    final user = profile.user;
    if (occasion == null || user == null) {
      throw ArgumentError('Deleting a profile requires occasion and user IDs');
    }
    return _invoke('delete_occasion_user_client_sync_v1', {
      'p_occasion': occasion,
      'p_user': user,
      'p_expected_version': profile.aggregateVersion,
    });
  }

  @override
  Future<ProfileCommandResult> create(OccasionUserModel profile) async {
    final occasion = profile.occasion;
    if (occasion == null || profile.user != null) {
      throw ArgumentError('Creating a profile requires only an occasion ID');
    }
    return _invoke('create_occasion_user_client_sync_v1', {
      'p_occasion': occasion,
      'p_profile': profile.toUpdateJson(),
    });
  }

  @override
  Future<ProfileCommandResult> save(OccasionUserModel profile) async {
    final occasion = profile.occasion;
    final user = profile.user;
    if (occasion == null || user == null) {
      throw ArgumentError('Saving a profile requires occasion and user IDs');
    }
    return _invoke('save_profile_client_sync_v1', {
      'p_occasion': occasion,
      'p_user': user,
      'p_expected_version': profile.aggregateVersion,
      'p_profile': profile.toUpdateJson(),
    });
  }

  Future<ProfileCommandResult> _invoke(
      String name, Map<String, dynamic> parameters) async {
    final actor = _actorId();
    final token = ClientSyncRuntime.mutationContextToken;
    final scoped = name == 'import_profiles_client_sync_v1' ||
        name == 'delete_occasion_user_client_sync_v1';
    final response = ClientCommandResponse.from(await (scoped
        ? _transport.invokeIntent(
            '$actor:${parameters['p_occasion']}:$name', name, parameters)
        : _transport.invoke(name, parameters)));
    if (actor == _actorId()) {
      await response.applyConfirmedReplacements(expectedContextToken: token);
    }
    return ProfileCommandResult(
      status: ProfileCommandStatus.values.byName(response.status),
      version: (response.data['version'] as num?)?.toInt() ?? 0,
      userId: response.data['userId'] as String?,
    );
  }
}
