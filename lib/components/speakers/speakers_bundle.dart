import 'speaker_model.dart';
import 'speaker_topic_model.dart';

/// The public get_speakers payload: visible speakers + topic catalog + the two
/// link sets. Cacheable in OfflineDataService. Provides lookup helpers so the
/// UI can resolve a lecture's speakers or a topic's counselors without extra
/// round-trips.
class SpeakersBundle {
  final List<SpeakerModel> speakers;
  final List<SpeakerTopicModel> topics;

  /// speaker id -> topic ids
  final Map<int, List<int>> topicsBySpeaker;

  /// topic id -> speaker ids
  final Map<int, List<int>> speakersByTopic;

  /// event id -> speaker ids
  final Map<int, List<int>> speakersByEvent;

  SpeakersBundle({
    required this.speakers,
    required this.topics,
    required this.topicsBySpeaker,
    required this.speakersByTopic,
    required this.speakersByEvent,
  });

  static SpeakersBundle empty() => SpeakersBundle(
        speakers: const [],
        topics: const [],
        topicsBySpeaker: const {},
        speakersByTopic: const {},
        speakersByEvent: const {},
      );

  factory SpeakersBundle.fromJson(Map<String, dynamic> json) {
    final speakers = ((json['speakers'] as List?) ?? const [])
        .map((e) => SpeakerModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final topics = ((json['speaker_topics'] as List?) ?? const [])
        .map((e) =>
            SpeakerTopicModel.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    final topicsBySpeaker = <int, List<int>>{};
    final speakersByTopic = <int, List<int>>{};
    for (final link in (json['speaker_topic_links'] as List?) ?? const []) {
      final m = (link as Map).cast<String, dynamic>();
      final s = (m['speaker'] as num).toInt();
      final t = (m['topic'] as num).toInt();
      (topicsBySpeaker[s] ??= []).add(t);
      (speakersByTopic[t] ??= []).add(s);
    }

    final speakersByEvent = <int, List<int>>{};
    for (final link in (json['event_speakers'] as List?) ?? const []) {
      final m = (link as Map).cast<String, dynamic>();
      final e = (m['event'] as num).toInt();
      final s = (m['speaker'] as num).toInt();
      (speakersByEvent[e] ??= []).add(s);
    }

    return SpeakersBundle(
      speakers: speakers,
      topics: topics,
      topicsBySpeaker: topicsBySpeaker,
      speakersByTopic: speakersByTopic,
      speakersByEvent: speakersByEvent,
    );
  }

  /// Round-trips through the same shape fromJson consumes (for offline cache).
  Map<String, dynamic> toJson() => {
        'speakers': speakers.map((s) => s.toJson()).toList(),
        'speaker_topics': topics.map((t) => t.toJson()).toList(),
        'speaker_topic_links': [
          for (final entry in topicsBySpeaker.entries)
            for (final t in entry.value)
              {'speaker': entry.key, 'topic': t},
        ],
        'event_speakers': [
          for (final entry in speakersByEvent.entries)
            for (final s in entry.value)
              {'event': entry.key, 'speaker': s},
        ],
      };

  SpeakerModel? speakerById(int id) {
    for (final s in speakers) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Visible speakers attached to [eventId], preserving speaker order.
  List<SpeakerModel> speakersForEvent(int eventId) {
    final ids = speakersByEvent[eventId] ?? const [];
    return speakers.where((s) => ids.contains(s.id)).toList();
  }
}
