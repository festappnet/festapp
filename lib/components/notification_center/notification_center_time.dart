import 'package:easy_localization/easy_localization.dart';

/// Calendar labels use the interface locale, independently of the device locale.
class NotificationCenterTime {
  static String _date(DateTime value, String locale) =>
      DateFormat.yMd(locale).format(value);

  /// Group days are calendar dates, not instants to shift into a time zone.
  static String day(DateTime value, String locale, {DateTime? now}) {
    final today = (now ?? DateTime.now()).toLocal();
    final days = DateTime.utc(today.year, today.month, today.day)
        .difference(DateTime.utc(value.year, value.month, value.day))
        .inDays;
    if (days == 0) return 'NotificationCenter.today'.tr();
    if (days == 1) return 'NotificationCenter.yesterday'.tr();
    return _date(value, locale);
  }

  static String timestamp(DateTime value, String locale, {DateTime? now}) {
    final local = value.toLocal();
    return 'NotificationCenter.atTime'.tr(namedArgs: {
      'day': day(local, locale, now: now),
      'time': DateFormat.jm(locale).format(local),
    });
  }

  static String exact(DateTime value, String locale) {
    final local = value.toLocal();
    return '${_date(local, locale)} ${DateFormat.jm(locale).format(local)}';
  }
}
