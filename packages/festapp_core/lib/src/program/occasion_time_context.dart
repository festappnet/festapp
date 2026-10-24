import 'package:timezone/timezone.dart' as tz;

/// The occasion timezone is supplied by the application when a value is
/// decoded/created. This preserves the existing instant versus wall-time rules.
class OccasionTimeContext {
  const OccasionTimeContext(this.location);
  final tz.Location location;

  DateTime toOccasionTime(DateTime value) {
    if (value is tz.TZDateTime || value.isUtc) {
      return tz.TZDateTime.from(value, location);
    }
    return tz.TZDateTime(
      location,
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    );
  }

  DateTime toUtc(DateTime value) {
    if (value is tz.TZDateTime) return value.toUtc();
    if (value.isUtc) return value;
    return tz.TZDateTime(
      location,
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
      value.microsecond,
    ).toUtc();
  }
}
