import 'package:flutter/foundation.dart';
import 'package:fstapp/components/speakers/counseling_availability.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';
import 'package:fstapp/components/speakers/speaker_commands.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Data access for the speakers + counseling feature. Backed by the SECURITY
/// DEFINER RPCs in database/functions/speakers/. Writes never touch the tables
/// directly (RLS is SELECT-only).
class DbSpeakers {
  static final _supabase = Supabase.instance.client;
  static final SpeakerCommands _commands = SupabaseSpeakerCommands(_supabase);
  static bool _publicReadUnavailable = false;

  // --- Public reads ---

  /// Visible speakers, topics and their links for an occasion (get_speakers).
  static Future<SpeakersBundle> getSpeakers(int occasionId,
      {bool includeDescription = false}) async {
    if (ClientSyncRuntime.isV1Selected) {
      return ClientSyncProjection.speakers();
    }
    if (_publicReadUnavailable) return SpeakersBundle.empty();
    dynamic res;
    try {
      res = await _supabase.rpc('get_speakers', params: {
        'p_occasion': occasionId,
        'p_include_description': includeDescription,
      });
    } on PostgrestException catch (error) {
      if (!isMissingSpeakersRpc(error)) rethrow;
      // Some still-supported legacy tenants predate the speakers migration.
      // Remember the capability result so event navigation does not repeat the
      // same failed request. Canonical backends use the projection above.
      _publicReadUnavailable = true;
      return SpeakersBundle.empty();
    }
    _ensureOk(res);
    return SpeakersBundle.fromJson(
        (res['data'] as Map).cast<String, dynamic>());
  }

  /// Counselors competent in [topicId] and their future slots, optionally
  /// scoped to a [from, to) window (the parent rozcestník event's day).
  static Future<CounselingAvailability> getCounselingAvailability(
      int occasionId, int topicId,
      {DateTime? from, DateTime? to}) async {
    final res = await _supabase.rpc('get_counseling_availability', params: {
      'p_occasion': occasionId,
      'p_topic': topicId,
      if (from != null) 'p_from': from.toUtc().toIso8601String(),
      if (to != null) 'p_to': to.toUtc().toIso8601String(),
    });
    _ensureOk(res);
    return CounselingAvailability.fromJson(
        (res['data'] as Map).cast<String, dynamic>());
  }

  /// Per-area availability (free / total future slots) for the rozcestník, so
  /// the client can grey out areas with nothing bookable
  /// (get_counseling_topics_overview).
  static Future<List<CounselingTopicOverview>> getCounselingTopicsOverview(
      int occasionId,
      {DateTime? from,
      DateTime? to}) async {
    final res = await _supabase.rpc('get_counseling_topics_overview', params: {
      'p_occasion': occasionId,
      if (from != null) 'p_from': from.toUtc().toIso8601String(),
      if (to != null) 'p_to': to.toUtc().toIso8601String(),
    });
    _ensureOk(res);
    return (((res['data'] as Map)['topics'] as List?) ?? const [])
        .map((e) => CounselingTopicOverview.fromJson(
            (e as Map).cast<String, dynamic>()))
        .toList();
  }

  // --- Admin reads ---

  /// All speakers (incl. hidden) with topics + linked events, plus the full
  /// topic catalog (get_speakers_for_edit).
  static Future<({List<SpeakerModel> speakers, List<SpeakerTopicModel> topics})>
      getSpeakersForEdit(int occasionId) async {
    final res = await _supabase.rpc(
        ClientSyncRuntime.isV1Selected
            ? 'get_speakers_editor_bundle_v1'
            : 'get_speakers_for_edit',
        params: {'p_occasion': occasionId});
    _ensureOk(res);
    final data = (res['data'] as Map).cast<String, dynamic>();
    final speakers = ((data['speakers'] as List?) ?? const [])
        .map((e) => SpeakerModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final topics = ((data['speaker_topics'] as List?) ?? const [])
        .map((e) =>
            SpeakerTopicModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    return (speakers: speakers, topics: topics);
  }

  // --- Admin writes (editor guarded server-side) ---

  static Future<SpeakerModel> updateSpeaker(
      int occasionId, SpeakerModel speaker) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.saveSpeaker(occasionId, speaker);
      if (result.status == SpeakerCommandStatus.conflict) {
        throw StateError('Speaker was changed by another editor');
      }
      if (result.status == SpeakerCommandStatus.rejected ||
          result.entity == null) {
        throw StateError('Speaker save was rejected');
      }
      return result.entity!;
    }
    final res = await _supabase.rpc('update_speaker', params: {
      'p_occasion': occasionId,
      'p_speaker': speaker.toJson(),
    });
    _ensureOk(res);
    return SpeakerModel.fromJson((res['data'] as Map).cast<String, dynamic>());
  }

  static Future<void> deleteSpeaker(SpeakerModel speaker) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.deleteSpeaker(
          RightsService.currentOccasionId()!, speaker);
      if (result.status == SpeakerCommandStatus.conflict) {
        throw StateError('Speaker was changed by another editor');
      }
      if (result.status == SpeakerCommandStatus.rejected) {
        throw StateError('Speaker delete was rejected');
      }
      return;
    }
    final res = await _supabase
        .rpc('delete_speaker', params: {'p_speaker_id': speaker.id});
    _ensureOk(res);
  }

  static Future<SpeakerTopicModel> updateTopic(
      int occasionId, SpeakerTopicModel topic) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.saveTopic(occasionId, topic);
      if (result.status == SpeakerCommandStatus.conflict) {
        throw StateError('Speaker topic was changed by another editor');
      }
      if (result.status == SpeakerCommandStatus.rejected ||
          result.entity == null) {
        throw StateError('Speaker topic save was rejected');
      }
      return result.entity!;
    }
    final res = await _supabase.rpc('update_speaker_topic', params: {
      'p_occasion': occasionId,
      'p_topic': topic.toJson(),
    });
    _ensureOk(res);
    return SpeakerTopicModel.fromJson(
        (res['data'] as Map).cast<String, dynamic>());
  }

  static Future<void> deleteTopic(SpeakerTopicModel topic) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.deleteTopic(
          RightsService.currentOccasionId()!, topic);
      if (result.status == SpeakerCommandStatus.conflict) {
        throw StateError('Speaker topic was changed by another editor');
      }
      if (result.status == SpeakerCommandStatus.rejected) {
        throw StateError('Speaker topic delete was rejected');
      }
      return;
    }
    final res = await _supabase
        .rpc('delete_speaker_topic', params: {'p_topic_id': topic.id});
    _ensureOk(res);
  }

  static Future<int> setEventSpeakers(
      int eventId, List<int> speakerIds, int expectedVersion) async {
    final result = await _commands.saveEventSpeakers(
      RightsService.currentOccasionId()!,
      eventId,
      expectedVersion,
      speakerIds,
    );
    if (result.status == SpeakerCommandStatus.conflict) {
      throw StateError('Event was changed by another editor');
    }
    if (result.status == SpeakerCommandStatus.rejected) {
      throw StateError('Event speaker save was rejected');
    }
    return result.version;
  }

  static Future<({int created, List<int> eventIds})> createCounselingSlots({
    required int speakerId,
    required DateTime start,
    required DateTime end,
    required int slotMinutes,
    int? placeId,
    int capacity = 1,
    String? title,
    int breakMinutes = 0,
  }) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.createCounselingSlots(
        speakerId: speakerId,
        start: start,
        end: end,
        slotMinutes: slotMinutes,
        placeId: placeId,
        capacity: capacity,
        title: title,
        breakMinutes: breakMinutes,
      );
      if (result.status == SpeakerCommandStatus.rejected) {
        throw StateError('Counseling slot creation was rejected');
      }
      return (created: result.count, eventIds: result.eventIds);
    }
    final res = await _supabase.rpc('create_counseling_slots', params: {
      'p_speaker': speakerId,
      'p_start': start.toUtc().toIso8601String(),
      'p_end': end.toUtc().toIso8601String(),
      'p_slot_minutes': slotMinutes,
      'p_place': placeId,
      'p_capacity': capacity,
      'p_title': title,
      'p_break_minutes': breakMinutes,
    });
    _ensureOk(res);
    final data = (res['data'] as Map).cast<String, dynamic>();
    return (
      created: (data['created'] as num).toInt(),
      eventIds: ((data['event_ids'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
    );
  }

  static Future<int> deleteEmptyCounselingSlots(int speakerId,
      {DateTime? from}) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result =
          await _commands.deleteEmptyCounselingSlots(speakerId, from: from);
      if (result.status == SpeakerCommandStatus.rejected) {
        throw StateError('Counseling slot deletion was rejected');
      }
      return result.count;
    }
    final res = await _supabase.rpc('delete_empty_counseling_slots', params: {
      'p_speaker': speakerId,
      'p_from': from?.toUtc().toIso8601String(),
    });
    _ensureOk(res);
    return ((res['data'] as Map)['deleted'] as num).toInt();
  }

  static Future<void> deleteCounselingSlot(
      int speakerId, SpeakerEventRef slot) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result = await _commands.deleteCounselingSlot(
        speakerId: speakerId,
        eventId: slot.id,
        expectedVersion: slot.aggregateVersion,
      );
      if (result.status == SpeakerCommandStatus.conflict) {
        throw StateError('Counseling slot was changed by another editor');
      }
      if (result.status == SpeakerCommandStatus.rejected || result.count != 1) {
        throw StateError(
            'Only a counseling slot owned by this speaker can be deleted');
      }
      return;
    }
    final res = await _supabase.rpc('delete_counseling_slot', params: {
      'p_speaker': speakerId,
      'p_event': slot.id,
    });
    _ensureOk(res);
  }

  static void _ensureOk(dynamic res) {
    if (res is Map && res['code'] != null && res['code'] != 200) {
      throw SpeakersException(
          (res['code'] as num).toInt(), res['message'] as String?);
    }
  }
}

@visibleForTesting
bool isMissingSpeakersRpc(PostgrestException error) =>
    error.code == 'PGRST202' ||
    (error.code == '404' && error.message.contains('get_speakers'));

/// Carries the RPC error code so the UI can show a matching message.
class SpeakersException implements Exception {
  final int code;
  final String? message;
  SpeakersException(this.code, this.message);

  @override
  String toString() => 'SpeakersException($code, $message)';
}
