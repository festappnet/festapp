import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

class PublishActivitiesResult {
  const PublishActivitiesResult({
    required this.status,
    required this.version,
    required this.historyId,
    this.draftId,
    this.latestPublishId,
  });

  final String status;
  final int version;
  final int? historyId;
  final int? draftId;
  final int? latestPublishId;
}

abstract interface class ActivityCommands {
  Future<PublishActivitiesResult> saveDraft(
      {required int occasionId,
      required int expectedVersion,
      required Map<String, dynamic> history,
      required int? parentHistoryId});
  Future<PublishActivitiesResult> discardDraft(
      {required int occasionId, required int? expectedDraftId});
  Future<PublishActivitiesResult> publish({
    required int occasionId,
    required int expectedVersion,
    required List<Map<String, dynamic>> activities,
    required Map<String, dynamic> history,
    required int? parentHistoryId,
  });
}

class SupabaseActivityCommands implements ActivityCommands {
  SupabaseActivityCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client),
        _actorId = (() => client.auth.currentUser?.id);

  SupabaseActivityCommands.withTransport(this._transport,
      {String? Function()? actorId})
      : _actorId = actorId ?? (() => null);

  final ClientCommandTransport _transport;
  final String? Function() _actorId;

  @override
  Future<PublishActivitiesResult> saveDraft(
          {required int occasionId,
          required int expectedVersion,
          required Map<String, dynamic> history,
          required int? parentHistoryId}) =>
      _invoke('save_activity_draft_client_sync_v1', {
        'p_occasion': occasionId,
        'p_expected_version': expectedVersion,
        'p_history_data': history,
        'p_parent_history_id': parentHistoryId
      });
  @override
  Future<PublishActivitiesResult> discardDraft(
          {required int occasionId, required int? expectedDraftId}) =>
      _invoke('discard_activity_draft_client_sync_v1',
          {'p_occasion': occasionId, 'p_expected_draft_id': expectedDraftId});

  @override
  Future<PublishActivitiesResult> publish({
    required int occasionId,
    required int expectedVersion,
    required List<Map<String, dynamic>> activities,
    required Map<String, dynamic> history,
    required int? parentHistoryId,
  }) async {
    return _invoke('publish_activities_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': expectedVersion,
      'p_activities_data': activities,
      'p_history_data': history,
      'p_parent_history_id': parentHistoryId,
    });
  }

  Future<PublishActivitiesResult> _invoke(
      String name, Map<String, dynamic> parameters) async {
    final token = ClientSyncRuntime.mutationContextToken;
    final actor = _actorId();
    final raw = await _transport.invokeIntent(
        '$actor:${parameters['p_occasion']}:$name', name, parameters);
    final response = ClientCommandResponse.from(raw);
    final data = response.data;
    if (actor == _actorId()) {
      await response.applyConfirmedReplacements(expectedContextToken: token);
    }
    return PublishActivitiesResult(
        status: response.status,
        version: (data['version'] as num).toInt(),
        historyId: (data['historyId'] as num?)?.toInt(),
        draftId: (data['draftId'] as num?)?.toInt(),
        latestPublishId: (data['latestPublishId'] as num?)?.toInt());
  }
}
