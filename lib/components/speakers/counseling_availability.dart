/// Result of get_counseling_availability: the counselors competent in the
/// chosen topic and their future free/occupied slots.
class CounselingAvailability {
  final List<CounselorModel> counselors;

  CounselingAvailability({required this.counselors});

  factory CounselingAvailability.fromJson(Map<String, dynamic> json) {
    return CounselingAvailability(
      counselors: ((json['counselors'] as List?) ?? const [])
          .map((e) =>
              CounselorModel.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class CounselorModel {
  final int id;
  final String? title;
  final String? subtitle;
  final String? image;
  final List<CounselingSlot> slots;

  CounselorModel({
    required this.id,
    this.title,
    this.subtitle,
    this.image,
    this.slots = const [],
  });

  factory CounselorModel.fromJson(Map<String, dynamic> json) {
    return CounselorModel(
      id: (json['id'] as num).toInt(),
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      image: json['image'] as String?,
      slots: ((json['slots'] as List?) ?? const [])
          .map((e) =>
              CounselingSlot.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Per-area availability summary from get_counseling_topics_overview: how many
/// future counseling slots an area has and how many are still free. Drives the
/// greyed-out state of areas that currently have nothing bookable.
class CounselingTopicOverview {
  final int topicId;
  final int totalFutureSlots;
  final int freeFutureSlots;

  const CounselingTopicOverview({
    required this.topicId,
    this.totalFutureSlots = 0,
    this.freeFutureSlots = 0,
  });

  bool get hasFree => freeFutureSlots > 0;

  factory CounselingTopicOverview.fromJson(Map<String, dynamic> json) =>
      CounselingTopicOverview(
        topicId: (json['id'] as num).toInt(),
        totalFutureSlots: (json['total_future_slots'] as num?)?.toInt() ?? 0,
        freeFutureSlots: (json['free_future_slots'] as num?)?.toInt() ?? 0,
      );
}

class CounselingSlot {
  final int id;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? place;
  final String? placeTitle;
  final int maxParticipants;
  final int occupied;
  final bool isSignedIn;

  CounselingSlot({
    required this.id,
    this.startTime,
    this.endTime,
    this.place,
    this.placeTitle,
    this.maxParticipants = 1,
    this.occupied = 0,
    this.isSignedIn = false,
  });

  bool get isFull => maxParticipants > 0 && occupied >= maxParticipants;

  factory CounselingSlot.fromJson(Map<String, dynamic> json) {
    return CounselingSlot(
      id: (json['id'] as num).toInt(),
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'].toString())?.toLocal()
          : null,
      endTime: json['end_time'] != null
          ? DateTime.tryParse(json['end_time'].toString())?.toLocal()
          : null,
      place: (json['place'] as num?)?.toInt(),
      placeTitle: json['place_title'] as String?,
      maxParticipants: (json['max_participants'] as num?)?.toInt() ?? 1,
      occupied: (json['occupied'] as num?)?.toInt() ?? 0,
      isSignedIn: json['isSignedIn'] as bool? ?? false,
    );
  }
}
