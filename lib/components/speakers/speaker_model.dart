/// A speaker (lecturer or counselor). Backed by public.speakers via the
/// speakers RPCs. A counselor is a speaker linked to one or more topics.
class SpeakerModel {
  final int? id;
  String? title; // name
  String? subtitle; // role / titles
  String? description; // HTML bio (only present when requested)
  String? image; // avatar URL
  int order;
  bool isHidden;
  Map<String, dynamic> data;
  int aggregateVersion;

  /// Competence topic ids (from get_speakers_for_edit / update_speaker).
  List<int> topics;

  /// Linked events with occupancy (admin only, from get_speakers_for_edit).
  List<SpeakerEventRef> events;

  SpeakerModel({
    this.id,
    this.title,
    this.subtitle,
    this.description,
    this.image,
    this.order = 0,
    this.isHidden = false,
    Map<String, dynamic>? data,
    List<int>? topics,
    List<SpeakerEventRef>? events,
    this.aggregateVersion = 0,
  })  : data = data ?? {},
        topics = topics ?? [],
        events = events ?? [];

  factory SpeakerModel.fromJson(Map<String, dynamic> json) {
    return SpeakerModel(
      id: (json['id'] as num?)?.toInt(),
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      image: json['image'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 0,
      isHidden: json['is_hidden'] as bool? ?? false,
      data: (json['data'] as Map?)?.cast<String, dynamic>() ?? {},
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ??
          (json['aggregateVersion'] as num?)?.toInt() ??
          0,
      topics:
          (json['topics'] as List?)?.map((e) => (e as num).toInt()).toList() ??
              [],
      events: (json['events'] as List?)
              ?.map((e) =>
                  SpeakerEventRef.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          [],
    );
  }

  /// Payload for update_speaker. Includes `topics` so the RPC replaces the
  /// competence links atomically; id omitted on insert.
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'image': image,
        'order': order,
        'is_hidden': isHidden,
        'data': data,
        'topics': topics,
      };
}

/// An event a speaker is attached to, with live occupancy (admin view).
class SpeakerEventRef {
  final int id;
  final String? title;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? maxParticipants;
  final int occupied;
  final bool isCounselingSlot;
  final int aggregateVersion;

  SpeakerEventRef({
    required this.id,
    this.title,
    this.startTime,
    this.endTime,
    this.maxParticipants,
    this.occupied = 0,
    this.isCounselingSlot = false,
    this.aggregateVersion = 0,
  });

  factory SpeakerEventRef.fromJson(Map<String, dynamic> json) {
    return SpeakerEventRef(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'].toString())?.toLocal()
          : null,
      endTime: json['end_time'] != null
          ? DateTime.tryParse(json['end_time'].toString())?.toLocal()
          : null,
      maxParticipants: (json['max_participants'] as num?)?.toInt(),
      occupied: (json['occupied'] as num?)?.toInt() ?? 0,
      isCounselingSlot: json['is_counseling_slot'] as bool? ?? false,
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
    );
  }
}
