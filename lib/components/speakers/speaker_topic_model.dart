/// One counseling/competence area (catalog entry per occasion).
/// Backed by public.speaker_topics via the speakers RPCs.
///
/// Areas have no code/key — the only identifier is the hidden primary key [id].
class SpeakerTopicModel {
  final int? id;
  String? title;
  int order;
  bool isHidden;
  int aggregateVersion;

  SpeakerTopicModel({
    this.id,
    this.title,
    this.order = 0,
    this.isHidden = false,
    this.aggregateVersion = 0,
  });

  factory SpeakerTopicModel.fromJson(Map<String, dynamic> json) {
    return SpeakerTopicModel(
      id: (json['id'] as num?)?.toInt(),
      title: json['title'] as String?,
      order: (json['order'] as num?)?.toInt() ?? 0,
      isHidden: json['is_hidden'] as bool? ?? false,
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ??
          (json['aggregateVersion'] as num?)?.toInt() ??
          0,
    );
  }

  /// Payload for update_speaker_topic (id omitted on insert).
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'title': title,
        'order': order,
        'is_hidden': isHidden,
      };
}
