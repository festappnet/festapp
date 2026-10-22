import 'package:fstapp/services/time_helper.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'occasion_sale_status.dart';

class OccasionSaleStrings {
  static String text(String key, [Map<String, String>? args]) =>
      'OccasionSales.$key'.tr(namedArgs: args);

  static String domainText(bool tickets, String key,
      [Map<String, String>? args]) {
    const domainKeys = {
      'scheduled',
      'selling',
      'soldOut',
      'startsIn',
      'shortStartsIn',
      'endsIn',
      'startsSoon',
      'endsSoon',
      'startsOn',
      'counts',
      'startAt',
      'endAt',
      'saleStart',
      'saleEnd',
      'countdown',
      'countdownHelp',
      'invalidTiming',
      'createScheduled',
      'createOpen',
      'salesLink',
      'privacy',
      'help',
      'completion',
      'question'
    };
    return domainKeys.contains(key.split('.').first)
        ? 'OccasionSales.${tickets ? 'ticketing' : 'registration'}.$key'
            .tr(namedArgs: args)
        : text(key, args);
  }

  static String duration(Duration remaining, Locale locale) {
    if (remaining.inDays > 0) {
      final count = remaining.inDays;
      String form(String key) => text('days.$key', {'count': '$count'});
      // Use CLDR rules explicitly; EasyLocalization otherwise skips few/many
      // by default. Czech, Slovak, Polish and Ukrainian need these forms.
      return Intl.plural(count,
          locale: locale.toLanguageTag(),
          one: form('one'),
          few: form('few'),
          many: form('many'),
          other: form('other'));
    }
    if (remaining.inHours > 0)
      return text('hours', {'count': '${remaining.inHours}'});
    return text('minutes',
        {'count': '${(remaining.inSeconds / 60).ceil().clamp(1, 59)}'});
  }

  static String label(OccasionSaleStatus status, DateTime now, Locale locale,
      {String? timezone, bool? hasTickets}) {
    String wording(String key, [Map<String, String>? args]) =>
        hasTickets == null
            ? text(key, args)
            : domainText(hasTickets, key, args);
    final deadline = status.deadline;
    if (deadline != null &&
        status.countdown &&
        (status.starts ||
            status.total == 1 && deadline.difference(now).inDays < 3)) {
      final remaining = deadline.difference(now);
      if (remaining.inSeconds < 60)
        return wording(status.starts ? 'startsSoon' : 'endsSoon');
      return wording(status.starts ? 'startsIn' : 'endsIn',
          {'duration': duration(remaining, locale)});
    }
    if (status.state == OccasionSaleState.scheduled && deadline != null) {
      return wording('startsOn', {
        'date': DateFormat.Md(locale.toLanguageTag())
            .format(deadline.toOccasionTime(timezone))
      });
    }
    final base = wording(status.state.name);
    return status.active > 0 && status.total > 1
        ? '$base ${status.active}/${status.total}'
        : base;
  }
}
