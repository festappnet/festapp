/// One feedback row for the current viewer (from get_event_feedback /
/// submit_event_feedback).
class EventFeedbackException implements Exception {
  final int code;
  final String? message;

  EventFeedbackException(this.code, this.message);
}

class EventFeedbackModel {
  final int? id;
  final int event;
  final String rating; // happy | neutral | sad
  final String? note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EventFeedbackModel({
    this.id,
    required this.event,
    required this.rating,
    this.note,
    this.createdAt,
    this.updatedAt,
  });

  static const String ratingHappy = 'happy';
  static const String ratingNeutral = 'neutral';
  static const String ratingSad = 'sad';

  factory EventFeedbackModel.fromJson(Map<String, dynamic> json) {
    return EventFeedbackModel(
      id: (json['id'] as num?)?.toInt(),
      event: (json['event'] as num).toInt(),
      rating: json['rating'] as String,
      note: json['note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())?.toLocal()
          : null,
    );
  }

  /// Mirror of [fromJson] for the offline "already sent" cache.
  Map<String, dynamic> toJson() => {
        'id': id,
        'event': event,
        'rating': rating,
        'note': note,
        'created_at': createdAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt?.toUtc().toIso8601String(),
      };
}

/// Aggregated counts for an event's feedback (admin view).
class EventFeedbackSummary {
  final int total;
  final int happy;
  final int neutral;
  final int sad;

  EventFeedbackSummary({
    this.total = 0,
    this.happy = 0,
    this.neutral = 0,
    this.sad = 0,
  });

  factory EventFeedbackSummary.fromJson(Map<String, dynamic> json) {
    return EventFeedbackSummary(
      total: (json['total'] as num?)?.toInt() ?? 0,
      happy: (json['happy'] as num?)?.toInt() ?? 0,
      neutral: (json['neutral'] as num?)?.toInt() ?? 0,
      sad: (json['sad'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One respondent row in the admin results list.
class EventFeedbackItem {
  final int? id;
  final String rating;
  final String? note;
  final String? userName;
  final bool isAnonymous;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  EventFeedbackItem({
    this.id,
    required this.rating,
    this.note,
    this.userName,
    this.isAnonymous = false,
    this.createdAt,
    this.updatedAt,
  });

  factory EventFeedbackItem.fromJson(Map<String, dynamic> json) {
    return EventFeedbackItem(
      id: (json['id'] as num?)?.toInt(),
      rating: json['rating'] as String,
      note: json['note'] as String?,
      userName: json['user_name'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())?.toLocal()
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())?.toLocal()
          : null,
    );
  }
}

class EventFeedbackForEdit {
  final EventFeedbackSummary summary;
  final List<EventFeedbackItem> items;

  EventFeedbackForEdit({required this.summary, required this.items});

  factory EventFeedbackForEdit.fromJson(Map<String, dynamic> json) {
    return EventFeedbackForEdit(
      summary: EventFeedbackSummary.fromJson(
          (json['summary'] as Map?)?.cast<String, dynamic>() ?? const {}),
      items: ((json['items'] as List?) ?? const [])
          .map((e) =>
              EventFeedbackItem.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
