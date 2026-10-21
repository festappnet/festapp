import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/past_occasion_years.dart';

void main() {
  List<OccasionModel> archive(int count, {bool oneYear = false}) =>
      List.generate(
          count,
          (i) => OccasionModel(isHidden: false, isOpen: true, isPromoted: false)
            ..startTime = DateTime.utc(oneYear || i < 5 ? 2026 : 2025, 5));

  test('groups large archives newest year first and preserves every event', () {
    final events = archive(9).reversed.toList();
    final groups = groupPastOccasionsByYear(events);
    expect(groups.keys, [2026, 2025]);
    expect(groups[2026], events.where((o) => o.startTime!.year == 2026));
    expect(groups.values.expand((v) => v).length, events.length);
  });

  test('short, single-year and incomplete archives remain flat', () {
    expect(groupPastOccasionsByYear(archive(8)), isEmpty);
    expect(groupPastOccasionsByYear(archive(9, oneYear: true)), isEmpty);
    expect(
        groupPastOccasionsByYear(archive(9)..first.startTime = null), isEmpty);
  });
}
