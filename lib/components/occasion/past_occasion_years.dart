import 'occasion_model.dart';

/// Keep short archives flat and every event visible, including incomplete dates.
Map<int, List<OccasionModel>> groupPastOccasionsByYear(
    List<OccasionModel> occasions) {
  if (occasions.length < 9 || occasions.any((o) => o.startTime == null)) {
    return {};
  }
  final grouped = <int, List<OccasionModel>>{};
  for (final occasion in occasions) {
    (grouped[occasion.startTime!.toUtc().year] ??= []).add(occasion);
  }
  if (grouped.length < 2) return {};
  return Map.fromEntries((grouped.keys.toList()..sort((a, b) => b.compareTo(a)))
      .map((year) => MapEntry(year, grouped[year]!)));
}
