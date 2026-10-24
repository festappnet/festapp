import '../../forms/waitlist_strings.dart';

class WaitlistSummaryModel {
  WaitlistSummaryModel.fromJson(Map<String, dynamic> json)
      : counts = Map<String, int>.from((json['counts'] as Map? ?? {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt()))),
        pendingPlaces = (json['pendingPlaces'] as num?)?.toInt() ?? 0,
        earliestExpiry =
            DateTime.tryParse(json['earliestExpiry']?.toString() ?? ''),
        isActive = json['isActive'] == true,
        allowedActions = Set<String>.from(json['allowedActions'] ?? []);
  final Map<String, int> counts;
  final int pendingPlaces;
  final DateTime? earliestExpiry;
  final bool isActive;
  final Set<String> allowedActions;
  String get label => counts.entries
      .where((e) => e.value > 0)
      .map((e) => '${e.value} ${WaitlistStrings.text(e.key)}')
      .join(' · ');
  Map<String, dynamic> toJson() => {
        'counts': counts,
        'pendingPlaces': pendingPlaces,
        'earliestExpiry': earliestExpiry?.toIso8601String(),
        'isActive': isActive,
        'allowedActions': allowedActions.toList()
      };
}
