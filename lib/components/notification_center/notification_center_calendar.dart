/// Device-local calendar intervals frozen at the acknowledged inbox snapshot.
/// Constructors, rather than 24-hour subtraction, preserve DST midnights.
class NotificationCenterCalendar {
  static List<Map<String, dynamic>> periods(
    DateTime snapshotAt,
    DateTime? oldestAt, {
    DateTime Function(DateTime)? localize,
    DateTime Function(int, int, int)? midnight,
  }) {
    final local = localize ?? (value) => value.toLocal();
    final day = midnight ?? (year, month, date) => DateTime(year, month, date);
    var end = snapshotAt.toUtc().subtract(const Duration(hours: 24));
    if (oldestAt == null || !oldestAt.isBefore(end)) return [];
    final anchor = local(snapshotAt);
    final dailyStart = day(anchor.year, anchor.month, anchor.day - 7).toUtc();
    final result = <Map<String, dynamic>>[];
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    while (end.isAfter(oldestAt)) {
      final last = local(end.subtract(const Duration(microseconds: 1)));
      final daily = end.isAfter(dailyStart);
      var start = day(
        last.year,
        last.month,
        daily ? last.day : last.day - last.weekday + 1,
      ).toUtc();
      if (daily && start.isBefore(dailyStart)) start = dailyStart;
      result.add({
        'unit': daily ? 'day' : 'week',
        'startAt': start.toIso8601String(),
        'endAt': end.toIso8601String(),
        'firstDay': date(local(start)),
        'lastDay': date(last),
      });
      end = start;
      if (result.length > 1024)
        throw StateError('Notification history exceeds calendar limit');
    }
    return result;
  }
}
