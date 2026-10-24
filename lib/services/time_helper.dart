import 'package:festapp_core/program.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/services/time_utils/platform_timezone_universal.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:timezone/timezone.dart' as tz;

class TimeHelper {
  static DateTime? currentTime;
  static OccasionTimeContext get eventTime => OccasionTimeContext(tz.local);
  static TimeZoneUniversal timeZoneUniversal = TimeZoneUniversal();

  static void Function()? toggleTimeTravel;

  static bool _timeagoLocalesReady = false;

  /// Humanized relative time ("před 4 hodinami" / "4 hours ago") for the given
  /// language code. Registers the non-default locale messages once (English is
  /// timeago's built-in default; other languages fall back to it). Shared by the
  /// offline banner and the news list so "how long ago" reads consistently.
  static String timeAgo(DateTime time, String langCode) {
    if (!_timeagoLocalesReady) {
      timeago.setLocaleMessages('cs', timeago.CsMessages());
      _timeagoLocalesReady = true;
    }
    return timeago.format(time.toLocal(), locale: langCode);
  }

  static DateTime now() {
    if (currentTime != null) {
      return currentTime!.toOccasionTime();
    }
    return tz.TZDateTime.now(tz.local);
  }

  static void setTimeZoneLocation([String? location]) {
    location ??= "Europe/Prague"; // Default location if none provided
    tz.Location targetLocation;
    try {
      targetLocation = tz.getLocation(location);
    } catch (e) {
      // Error getting location, defaulting to Europe/Prague
      targetLocation =
          tz.getLocation("Europe/Prague"); // Fallback to a known good default
    }

    timeZoneUniversal.setTimeZoneLocationPlatform(
        targetLocation); // Uses conditionally imported method

    DateTime nowInTz = tz.TZDateTime.now(tz.local);

  }

  static List<String> getAvailableTimezoneNames() {
    // Ensure the database is initialized before accessing locations.
    // This typically happens once at app startup via initializeTimeZone().
    return tz.timeZoneDatabase.locations.keys.toList()..sort();
  }

  static int getTimeNowIndexFromDays(Iterable<int> weekdays) {
    var index = weekdays.toList().indexOf(now().weekday);
    if (index == -1) {
      return 0;
    }
    return index;
  }

  static double differenceInHours(DateTime start, DateTime end) {
    int differenceInMillis = end.difference(start).inMilliseconds;
    double hoursDifference = differenceInMillis / (1000 * 60 * 60);
    return hoursDifference;
  }

  static Future<TimeOfDay?> showUniversalTimePicker({
    required BuildContext context,
    required TimeOfDay initialTime,
    TimePickerEntryMode initialEntryMode = TimePickerEntryMode.dial,
  }) async {
    return await showTimePicker(
      context: context,
      initialTime: initialTime,
      initialEntryMode: initialEntryMode,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
  }

  static String getMinimalisticDateRange(
      BuildContext context, DateTime start, DateTime end) {
    final locale = Localizations.localeOf(context).languageCode;
    final fullFormat = DateFormat.yMMMd(locale);

    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return fullFormat.format(end);
    }

    final fullEnd = fullFormat.format(end);
    String minimalStart;

    if (start.year == end.year) {
      if (start.month == end.month) {
        minimalStart = DateFormat.d(locale).format(start);
      } else {
        minimalStart = DateFormat.MMMd(locale).format(start);
      }
    } else {
      minimalStart = fullFormat.format(start);
    }

    return '$minimalStart - $fullEnd';
  }

  static String getSystemTimezoneName() {
    final systemNow = DateTime.now();
    final systemUtcOffset = systemNow.timeZoneOffset;

    List<String> availableTimezones = getAvailableTimezoneNames();

    List<String> europeanTimezones = availableTimezones
        .where((name) => name.startsWith("Europe/"))
        .toList()
      ..sort();

    List<String> africanTimezones = availableTimezones
        .where((name) => name.startsWith("Africa/"))
        .toList()
      ..sort();

    List<String> preferredOrderTimezones = [
      ...europeanTimezones,
      ...africanTimezones,
      ...availableTimezones.where(
          (name) => !name.startsWith("Europe/") && !name.startsWith("Africa/"))
    ];

    for (final locationName in preferredOrderTimezones) {
      try {
        final location = tz.getLocation(locationName);
        final tzDateTime = tz.TZDateTime.from(systemNow, location);
        if (tzDateTime.timeZoneOffset == systemUtcOffset) {
          return locationName;
        }
      } catch (e) {

      }
    }

    return "UTC";
  }

  static Future<void> initializeTimeZone() async {
    await timeZoneUniversal.initializeTimeZonePlatform();
  }
}

extension DateTimeExtension on DateTime {
  DateTime roundDown({Duration delta = const Duration(hours: 1)}) {
    final ms = millisecondsSinceEpoch;
    final roundedMs = ms - ms % delta.inMilliseconds;
    if (this is tz.TZDateTime) {
      return tz.TZDateTime.fromMillisecondsSinceEpoch(
          (this as tz.TZDateTime).location, roundedMs);
    }
    return DateTime.fromMillisecondsSinceEpoch(roundedMs, isUtc: isUtc);
  }

  DateTime roundUp({Duration delta = const Duration(hours: 1)}) {
    final ms = millisecondsSinceEpoch;
    final mod = ms % delta.inMilliseconds;
    if (mod == 0) {
      return this;
    }
    final roundedMs = ms - mod + delta.inMilliseconds;
    if (this is tz.TZDateTime) {
      return tz.TZDateTime.fromMillisecondsSinceEpoch(
          (this as tz.TZDateTime).location, roundedMs);
    }
    return DateTime.fromMillisecondsSinceEpoch(roundedMs, isUtc: isUtc);
  }

  double get hourInDouble {
    return hour + minute / 60.0 + second / 3600.0;
  }

  String weekdayToString(BuildContext context) {
    return DateFormat("EEEE", context.locale.languageCode).format(this);
  }

  DateTime toOccasionTime([String? targetTimezoneName]) =>
      OccasionTimeContext(targetTimezoneName == null ? tz.local : tz.getLocation(targetTimezoneName)).toOccasionTime(this);

  DateTime toUtcFromOccasionTime([String? sourceTimezoneName]) =>
      OccasionTimeContext(sourceTimezoneName == null ? tz.local : tz.getLocation(sourceTimezoneName)).toUtc(this);

}
