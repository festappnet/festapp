import 'package:timezone/data/latest_all.dart' as database;
import 'package:timezone/timezone.dart' as tz;

/// The occasion timezone is supplied by the application when a value is
/// decoded/created. This preserves the existing instant versus wall-time rules.
class OccasionTimeContext {
  const OccasionTimeContext(this.location);
  final tz.Location location;

  /// One embedded dataset for every platform; full data retains saved IANA aliases.
  static void initializeTimeZones() => database.initializeTimeZones();

  static const defaultLocationName = 'Europe/Prague';

  factory OccasionTimeContext.local() => OccasionTimeContext(tz.local);

  /// Explicit names remain strict; invalid persisted selections use the separate
  /// application selection boundary below, rather than changing conversion rules.
  factory OccasionTimeContext.named(String name) =>
      OccasionTimeContext(tz.getLocation(name));

  static List<String> get availableLocationNames =>
      tz.timeZoneDatabase.locations.keys.toList()..sort();

  static void setLocalLocation([String? name]) {
    tz.Location target;
    try {
      target = OccasionTimeContext.named(name ?? defaultLocationName).location;
    } catch (_) {
      target = OccasionTimeContext.named(defaultLocationName).location;
    }
    tz.setLocalLocation(target);
  }

  DateTime now() => tz.TZDateTime.now(location);

  /// Convert an instant even when it is represented by a device-local DateTime.
  DateTime atInstant(DateTime instant) => tz.TZDateTime.from(instant, location);

  DateTime toOccasionTime(DateTime value) {
    if (value is tz.TZDateTime || value.isUtc) {
      return atInstant(value);
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

  /// Minute-precision scheduling rejects missing DST times and returns both
  /// repeated instants. General event conversion keeps its existing normalization.
  List<DateTime> instantsForWallTime(DateTime wall) {
    final nominal = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
    );
    final results = <DateTime>[];
    for (final offset in location.zones.map((z) => z.offset).toSet()) {
      final instant = nominal.subtract(offset);
      final local = atInstant(instant);
      if (local.year == wall.year &&
          local.month == wall.month &&
          local.day == wall.day &&
          local.hour == wall.hour &&
          local.minute == wall.minute) {
        results.add(instant);
      }
    }
    return results..sort();
  }
}
