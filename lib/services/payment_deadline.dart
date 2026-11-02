import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'locale_date_time.dart';
import 'time_helper.dart';

/// The exact local deadline with a future-only, localized reading aid.
/// Payment state (including overdue) remains owned by the server.
abstract final class PaymentDeadline {
  static bool _localesReady = false;

  static String format(dynamic value, String locale) {
    final exact = LocaleDateTime.instant(value, locale);
    final deadline = value is DateTime
        ? value
        : DateTime.tryParse('${value ?? ''}');
    if (deadline == null) return exact;
    final now = TimeHelper.currentTime ?? DateTime.now();
    if (!deadline.isAfter(now)) return exact;
    if (!_localesReady) {
      for (final language in _futureForms.keys) {
        timeago.setLocaleMessages(
          'payment_future_$language',
          _FutureMessages(language),
        );
      }
      _localesReady = true;
    }
    final language = locale.split(RegExp('[-_]')).first;
    // Unsupported languages retain the exact date instead of mixing languages.
    if (!_futureForms.containsKey(language)) return exact;
    final relative = timeago.format(
      deadline,
      clock: now,
      allowFromNow: true,
      locale: 'payment_future_$language',
    );
    return '$exact ($relative)';
  }
}

// timeago's bundled messages primarily use past-tense cases and omit Slovak.
// Keep future messages separate so existing news/offline timeAgo stays intact.
// Each unit is [one, few, other]; Intl owns the language's CLDR plural rules.
const _futureForms = <String, List<List<String>>>{
  'cs': [
    ['minutu', 'minuty', 'minut'],
    ['hodinu', 'hodiny', 'hodin'],
    ['den', 'dny', 'dní'],
    ['měsíc', 'měsíce', 'měsíců'],
    ['rok', 'roky', 'let'],
  ],
  'sk': [
    ['minútu', 'minúty', 'minút'],
    ['hodinu', 'hodiny', 'hodín'],
    ['deň', 'dni', 'dní'],
    ['mesiac', 'mesiace', 'mesiacov'],
    ['rok', 'roky', 'rokov'],
  ],
  'en': [
    ['a minute', 'minutes', 'minutes'],
    ['an hour', 'hours', 'hours'],
    ['a day', 'days', 'days'],
    ['a month', 'months', 'months'],
    ['a year', 'years', 'years'],
  ],
  'de': [
    ['einer Minute', 'Minuten', 'Minuten'],
    ['einer Stunde', 'Stunden', 'Stunden'],
    ['einem Tag', 'Tagen', 'Tagen'],
    ['einem Monat', 'Monaten', 'Monaten'],
    ['einem Jahr', 'Jahren', 'Jahren'],
  ],
  'pl': [
    ['minutę', 'minuty', 'minut'],
    ['godzinę', 'godziny', 'godzin'],
    ['dzień', 'dni', 'dni'],
    ['miesiąc', 'miesiące', 'miesięcy'],
    ['rok', 'lata', 'lat'],
  ],
  'uk': [
    ['хвилину', 'хвилини', 'хвилин'],
    ['годину', 'години', 'годин'],
    ['день', 'дні', 'днів'],
    ['місяць', 'місяці', 'місяців'],
    ['рік', 'роки', 'років'],
  ],
};

class _FutureMessages implements timeago.LookupMessages {
  _FutureMessages(this.locale);
  final String locale;

  String _unit(int count, int unit, {bool singular = false}) {
    final forms = _futureForms[locale]![unit];
    return Intl.plural(
      count,
      locale: locale,
      one: singular ? forms[0] : '$count ${forms[0]}',
      few: '$count ${forms[1]}',
      many: '$count ${forms[2]}',
      other: '$count ${forms[2]}',
    );
  }

  @override
  String prefixFromNow() => const {
    'cs': 'za',
    'sk': 'za',
    'en': 'in',
    'de': 'in',
    'pl': 'za',
    'uk': 'через',
  }[locale]!;
  @override
  String suffixFromNow() => '';
  @override
  String prefixAgo() => '';
  @override
  String suffixAgo() => '';
  @override
  String wordSeparator() => ' ';
  @override
  String lessThanOneMinute(int seconds) => const {
    'cs': 'chvíli',
    'sk': 'chvíľu',
    'en': 'a moment',
    'de': 'einem Moment',
    'pl': 'chwilę',
    'uk': 'мить',
  }[locale]!;
  @override
  String aboutAMinute(int minutes) => _unit(1, 0, singular: true);
  @override
  String minutes(int minutes) => _unit(minutes, 0);
  @override
  String aboutAnHour(int minutes) => _unit(1, 1, singular: true);
  @override
  String hours(int hours) => _unit(hours, 1);
  @override
  String aDay(int hours) => _unit(1, 2, singular: true);
  @override
  String days(int days) => _unit(days, 2);
  @override
  String aboutAMonth(int days) => _unit(1, 3, singular: true);
  @override
  String months(int months) => _unit(months, 3);
  @override
  String aboutAYear(int year) => _unit(1, 4, singular: true);
  @override
  String years(int years) => _unit(years, 4);
}
