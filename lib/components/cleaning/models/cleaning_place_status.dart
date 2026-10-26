import 'package:fstapp/components/cleaning/cleaning_status.dart';

/// Public per-toilet status (from get_cleaning_status): id, title/number, the
/// derived status and the time of the most recent open report. No notes/names.
class CleaningPlaceStatus {
  final int place;
  final String title;
  final CleaningStatus status;
  final DateTime? lastReportedAt;

  CleaningPlaceStatus({
    required this.place,
    required this.title,
    required this.status,
    this.lastReportedAt,
  });

  factory CleaningPlaceStatus.fromJson(Map<String, dynamic> json) {
    return CleaningPlaceStatus(
      place: (json['place'] as num).toInt(),
      title: (json['title'] as String?) ?? '',
      status: CleaningStatusHelper.fromCode(json['status'] as String?),
      lastReportedAt: json['last_reported_at'] != null
          ? DateTime.tryParse(json['last_reported_at'].toString())?.toLocal()
          : null,
    );
  }

  /// Mirror of [fromJson] for the offline cache; the enum's name equals its
  /// status code, so a cached entry round-trips through fromJson unchanged.
  Map<String, dynamic> toJson() => {
        'place': place,
        'title': title,
        'status': status.name,
        'last_reported_at': lastReportedAt?.toUtc().toIso8601String(),
      };
}
