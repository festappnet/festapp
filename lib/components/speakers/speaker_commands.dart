import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:festapp_core/sync.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum SpeakerCommandStatus { applied, unchanged, rejected, conflict }

class SpeakerCommandResult<T> {
  const SpeakerCommandResult({
    required this.status,
    required this.version,
    this.entity,
  });

  final SpeakerCommandStatus status;
  final int version;
  final T? entity;
}

class EventSpeakersCommandResult {
  const EventSpeakersCommandResult({
    required this.status,
    required this.version,
    required this.speakerIds,
  });

  final SpeakerCommandStatus status;
  final int version;
  final List<int> speakerIds;
}

class CounselingSlotsCommandResult {
  const CounselingSlotsCommandResult({
    required this.status,
    required this.count,
    this.eventIds = const [],
  });

  final SpeakerCommandStatus status;
  final int count;
  final List<int> eventIds;
}

abstract interface class SpeakerCommands {
  Future<SpeakerCommandResult<SpeakerModel>> saveSpeaker(
      int occasionId, SpeakerModel speaker);
  Future<SpeakerCommandResult<SpeakerModel>> deleteSpeaker(
      int occasionId, SpeakerModel speaker);
  Future<SpeakerCommandResult<SpeakerTopicModel>> saveTopic(
      int occasionId, SpeakerTopicModel topic);
  Future<SpeakerCommandResult<SpeakerTopicModel>> deleteTopic(
      int occasionId, SpeakerTopicModel topic);
  Future<EventSpeakersCommandResult> saveEventSpeakers(
    int occasionId,
    int eventId,
    int expectedVersion,
    List<int> speakerIds,
  );
  Future<CounselingSlotsCommandResult> createCounselingSlots({
    required int speakerId,
    required DateTime start,
    required DateTime end,
    required int slotMinutes,
    int? placeId,
    int capacity,
    String? title,
    int breakMinutes,
  });
  Future<CounselingSlotsCommandResult> deleteEmptyCounselingSlots(
    int speakerId, {
    DateTime? from,
  });
  Future<CounselingSlotsCommandResult> deleteCounselingSlot({
    required int speakerId,
    required int eventId,
    required int expectedVersion,
  });
}

class SupabaseSpeakerCommands implements SpeakerCommands {
  SupabaseSpeakerCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseSpeakerCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<CounselingSlotsCommandResult> createCounselingSlots({
    required int speakerId,
    required DateTime start,
    required DateTime end,
    required int slotMinutes,
    int? placeId,
    int capacity = 1,
    String? title,
    int breakMinutes = 0,
  }) async {
    final response = await _invoke('create_counseling_slots_client_sync_v1', {
      'p_speaker': speakerId,
      'p_start': start.toUtc().toIso8601String(),
      'p_end': end.toUtc().toIso8601String(),
      'p_slot_minutes': slotMinutes,
      'p_place': placeId,
      'p_capacity': capacity,
      'p_title': title,
      'p_break_minutes': breakMinutes,
    });
    final eventIds = ((response.data['event_ids'] as List?) ?? const [])
        .map((id) => (id as num).toInt())
        .toList(growable: false);
    return CounselingSlotsCommandResult(
      status: SpeakerCommandStatus.values.byName(response.status),
      count: (response.data['created'] as num?)?.toInt() ?? eventIds.length,
      eventIds: eventIds,
    );
  }

  @override
  Future<CounselingSlotsCommandResult> deleteEmptyCounselingSlots(
    int speakerId, {
    DateTime? from,
  }) async {
    final response =
        await _invoke('delete_empty_counseling_slots_client_sync_v1', {
      'p_speaker': speakerId,
      'p_from': from?.toUtc().toIso8601String(),
    });
    return CounselingSlotsCommandResult(
      status: SpeakerCommandStatus.values.byName(response.status),
      count: (response.data['deleted'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<CounselingSlotsCommandResult> deleteCounselingSlot({
    required int speakerId,
    required int eventId,
    required int expectedVersion,
  }) async {
    final response = await _invoke('delete_counseling_slot_client_sync_v1', {
      'p_speaker': speakerId,
      'p_event_id': eventId,
      'p_expected_version': expectedVersion,
    });
    return CounselingSlotsCommandResult(
      status: SpeakerCommandStatus.values.byName(response.status),
      count: response.data['deleted'] == true ? 1 : 0,
      eventIds: response.data['deleted'] == true ? [eventId] : const [],
    );
  }

  @override
  Future<SpeakerCommandResult<SpeakerModel>> saveSpeaker(
      int occasionId, SpeakerModel speaker) async {
    final response = await _invoke('save_speaker_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version':
          speaker.id == null ? null : speaker.aggregateVersion,
      'p_speaker': speaker.toJson(),
    });
    return _speakerResult(response);
  }

  @override
  Future<SpeakerCommandResult<SpeakerModel>> deleteSpeaker(
      int occasionId, SpeakerModel speaker) async {
    final id = speaker.id;
    if (id == null) throw ArgumentError('Deleting a speaker requires its ID');
    final response = await _invoke('delete_speaker_client_sync_v1', {
      'p_occasion': occasionId,
      'p_speaker_id': id,
      'p_expected_version': speaker.aggregateVersion,
    });
    return _speakerResult(response);
  }

  @override
  Future<SpeakerCommandResult<SpeakerTopicModel>> saveTopic(
      int occasionId, SpeakerTopicModel topic) async {
    final response = await _invoke('save_speaker_topic_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': topic.id == null ? null : topic.aggregateVersion,
      'p_topic': topic.toJson(),
    });
    return _topicResult(response);
  }

  @override
  Future<SpeakerCommandResult<SpeakerTopicModel>> deleteTopic(
      int occasionId, SpeakerTopicModel topic) async {
    final id = topic.id;
    if (id == null) throw ArgumentError('Deleting a topic requires its ID');
    final response = await _invoke('delete_speaker_topic_client_sync_v1', {
      'p_occasion': occasionId,
      'p_topic_id': id,
      'p_expected_version': topic.aggregateVersion,
    });
    return _topicResult(response);
  }

  @override
  Future<EventSpeakersCommandResult> saveEventSpeakers(
    int occasionId,
    int eventId,
    int expectedVersion,
    List<int> speakerIds,
  ) async {
    final response = await _invoke('save_event_speakers_client_sync_v1', {
      'p_occasion': occasionId,
      'p_event': eventId,
      'p_expected_version': expectedVersion,
      'p_speaker_ids': [...speakerIds]..sort(),
    });
    final data = response.data;
    return EventSpeakersCommandResult(
      status: SpeakerCommandStatus.values.byName(response.status),
      version: (data['version'] as num?)?.toInt() ?? 0,
      speakerIds: ((data['speakerIds'] as List?) ?? const [])
          .map((id) => (id as num).toInt())
          .toList(growable: false),
    );
  }

  Future<ClientCommandResponse> _invoke(
      String functionName, Map<String, dynamic> parameters) async {
    final response = ClientCommandResponse.from(
        await _transport.invoke(functionName, parameters));
    await applyClientCommandReplacements(response);
    return response;
  }

  SpeakerCommandResult<SpeakerModel> _speakerResult(
      ClientCommandResponse response) {
    final data = response.data;
    final version = (data['version'] as num?)?.toInt() ?? 0;
    final raw = data['speaker'];
    return SpeakerCommandResult(
      status: SpeakerCommandStatus.values.byName(response.status),
      version: version,
      entity: raw is Map
          ? SpeakerModel.fromJson({
              ...raw.cast<String, dynamic>(),
              'aggregate_version': version,
            })
          : null,
    );
  }

  SpeakerCommandResult<SpeakerTopicModel> _topicResult(
      ClientCommandResponse response) {
    final data = response.data;
    final version = (data['version'] as num?)?.toInt() ?? 0;
    final raw = data['topic'];
    return SpeakerCommandResult(
      status: SpeakerCommandStatus.values.byName(response.status),
      version: version,
      entity: raw is Map
          ? SpeakerTopicModel.fromJson({
              ...raw.cast<String, dynamic>(),
              'aggregate_version': version,
            })
          : null,
    );
  }
}
