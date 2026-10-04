import 'package:timezone/timezone.dart' as tz;

/// Calendar day in the same timezone as the report's SQL order buckets.
DateTime reportDay(DateTime instant) {
  final local = tz.TZDateTime.from(instant, tz.getLocation('Europe/Prague'));
  return DateTime.utc(local.year, local.month, local.day);
}

/// Completed occasions end at their closing date, extended by actual activity.
/// Without an occasion end date, use the last activity rather than empty days.
DateTime reportTimelineEnd({
  required DateTime today,
  required DateTime lastActivity,
  DateTime? occasionEnd,
}) {
  final boundary = occasionEnd == null
      ? lastActivity
      : occasionEnd.isBefore(today)
          ? occasionEnd
          : today;
  return lastActivity.isAfter(boundary) ? lastActivity : boundary;
}
