import 'package:intl/intl.dart';

/// Display adapters for canonical grid values. The underlying value remains
/// unchanged so sorting, filtering and editor/RPC round trips keep their types.
class LocaleDateTime {
  static String dateCell(dynamic value, String locale) {
    final date = _parse(value);
    return date == null
        ? '${value ?? ''}'
        : DateFormat.yMd(locale).format(date);
  }

  static String dateTimeCell(dynamic value, String locale,
      {bool seconds = false}) {
    final date = _parse(value);
    if (date == null) return '${value ?? ''}';
    return (seconds
            ? DateFormat.yMd(locale).add_jms()
            : DateFormat.yMd(locale).add_jm())
        .format(date);
  }

  static String timeCell(dynamic value, String locale) {
    final date = DateTime.tryParse('2000-01-01 $value');
    return date == null ? '${value ?? ''}' : DateFormat.jm(locale).format(date);
  }

  static String instant(dynamic value, String locale, {bool seconds = false}) {
    final date = _parse(value);
    return date == null
        ? '${value ?? ''}'
        : dateTimeCell(date.toLocal(), locale, seconds: seconds);
  }

  static DateTime? _parse(dynamic value) =>
      value is DateTime ? value : DateTime.tryParse('${value ?? ''}');
}
