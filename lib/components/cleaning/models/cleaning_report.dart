/// A single open (or resolved) cleaning report as seen by the crew
/// (from get_cleaning_reports): includes note, reporter and times.
class CleaningReport {
  final int id;
  final int place;
  final String placeTitle;
  final String problemType;
  final String? note;
  final List<String> extraNotes;
  final DateTime createdAt;
  final String? createdBy;
  final String? createdByName;
  final bool createdByBlocked;
  final DateTime? resolvedAt;

  CleaningReport({
    required this.id,
    required this.place,
    required this.placeTitle,
    required this.problemType,
    this.note,
    this.extraNotes = const [],
    required this.createdAt,
    this.createdBy,
    this.createdByName,
    this.createdByBlocked = false,
    this.resolvedAt,
  });

  factory CleaningReport.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final extra = <String>[];
    if (data is Map && data['extra_notes'] is List) {
      for (final n in (data['extra_notes'] as List)) {
        if (n != null) extra.add(n.toString());
      }
    }
    final name = (json['created_by_name'] as String?)?.trim();
    return CleaningReport(
      id: (json['id'] as num).toInt(),
      place: (json['place'] as num).toInt(),
      placeTitle: (json['place_title'] as String?) ?? '',
      problemType: (json['problem_type'] as String?) ?? '',
      note: (json['note'] as String?),
      extraNotes: extra,
      createdAt:
          DateTime.tryParse(json['created_at'].toString())?.toLocal() ??
              DateTime.now(),
      createdBy: (json['created_by'] as String?),
      createdByName: (name == null || name.isEmpty) ? null : name,
      createdByBlocked: json['created_by_blocked'] == true,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.tryParse(json['resolved_at'].toString())?.toLocal()
          : null,
    );
  }
}
