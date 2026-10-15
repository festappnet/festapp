import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:festapp_core/program.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:festapp_core/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/schedule/event_commands.dart';

/// Statically bound event command adapter. RPC names are implementation
/// details and cannot be selected by feature/UI callers.
class SupabaseEventCommands implements EventCommands {
  SupabaseEventCommands(SupabaseClient client,
      {bool Function()? useClientSyncDelete})
      : _transport = ClientCommandTransport.supabase(client),
        _legacyDelete =
            ((id) => client.rpc('delete_event', params: {'p_event': id})),
        _useClientSyncDelete = useClientSyncDelete ?? (() => true);

  final ClientCommandTransport _transport;
  final Future<Object?> Function(int?) _legacyDelete;
  final bool Function() _useClientSyncDelete;

  @override
  Future<EventCommandResult> save(EventModel event) async {
    final occasionId = event.occasionId;
    if (occasionId == null) {
      throw ArgumentError.value(occasionId, 'event.occasionId');
    }
    final raw = await _transport.invoke('save_event_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': event.id == null ? null : event.aggregateVersion,
      'p_event': _dto(event),
    });
    return _decode(raw, timeContext: event.timeContext);
  }

  @override
  Future<EventCommandResult> delete(EventModel event) async {
    if (!_useClientSyncDelete()) {
      final raw = await _legacyDelete(event.id);
      final code = raw is Map && raw['code'] != null
          ? (raw['code'] as num).toInt()
          : null;
      if (code != 200) throw Exception('delete_event failed with code $code');
      return EventCommandResult(
          status: EventCommandStatus.applied, version: event.aggregateVersion);
    }
    final occasionId = event.occasionId;
    final eventId = event.id;
    if (occasionId == null || eventId == null) {
      throw ArgumentError('Deleting an event requires occasion and event IDs');
    }
    final raw = await _transport.invoke('delete_event_client_sync_v1', {
      'p_occasion': occasionId,
      'p_event_id': eventId,
      'p_expected_version': event.aggregateVersion,
    });
    return _decode(raw, timeContext: event.timeContext);
  }

  Map<String, dynamic> _dto(EventModel event) => {
        if (event.id case final id?) 'id': id,
        'title': event.title,
        'startTime': event.timeContext.toUtc(event.startTime).toIso8601String(),
        'endTime': event.timeContext.toUtc(event.endTime).toIso8601String(),
        'maxParticipants': event.maxParticipants,
        'description': event.description,
        'placeId': event.place?.id,
        'splitForMenWomen': event.splitForMenWomen ?? false,
        'isGroupEvent': event.isGroupEvent ?? false,
        'isHidden': event.isHidden ?? false,
        'type': event.type,
        'data': event.toUpsertMap()[EventModel.dataColumn],
        'order': event.order,
        'parentEventIds': [...?event.parentEventIds]..sort(),
        'eventRoleIds': [...?event.eventRolesIds]..sort(),
      };

  Future<EventCommandResult> _decode(Object? raw,
      {required OccasionTimeContext timeContext}) async {
    final response = ClientCommandResponse.from(raw);
    await applyClientCommandReplacements(response);
    final status = EventCommandStatus.values.byName(response.status);
    final data = response.data;
    final eventJson = data['event'];
    final version = (data['version'] as num?)?.toInt() ?? 0;
    final event = eventJson is Map
        ? EventModel.fromCommandJson(eventJson.cast<String, dynamic>(), version,
            timeContext: timeContext)
        : null;
    return EventCommandResult(status: status, version: version, event: event);
  }
}
