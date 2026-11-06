import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fstapp/services/locale_date_time.dart';
import 'package:fstapp/services/payment_deadline.dart';
import 'package:fstapp/services/time_helper.dart';

void main() {
  final clock = DateTime.utc(2026, 11, 2, 12);
  setUpAll(() async {
    await initializeDateFormatting();
    await TimeHelper.initializeTimeZone();
  });
  setUp(() {
    final previous = TimeHelper.currentTime;
    TimeHelper.currentTime = clock;
    addTearDown(() => TimeHelper.currentTime = previous);
  });

  const expected = {
    'cs': ['za den', 'za 3 dny', 'za 5 dní'],
    'sk': ['za deň', 'za 3 dni', 'za 5 dní'],
    'en': ['in a day', 'in 3 days', 'in 5 days'],
    'de': ['in einem Tag', 'in 3 Tagen', 'in 5 Tagen'],
    'pl': ['za dzień', 'za 3 dni', 'za 5 dni'],
    'uk': ['через день', 'через 3 дні', 'через 5 днів'],
  };
  for (final entry in expected.entries) {
    test('${entry.key} future uses CLDR forms and keeps exact local date', () {
      for (var index = 0; index < 3; index++) {
        final deadline = clock.add(Duration(days: [1, 3, 5][index]));
        final raw = deadline.toIso8601String();
        expect(
          PaymentDeadline.format(raw, entry.key),
          '${LocaleDateTime.instant(raw, entry.key)} (${entry.value[index]})',
        );
      }
    });
  }

  test('Czech future hours and minutes use future grammatical cases', () {
    for (final entry in {
      const Duration(seconds: 20): 'za chvíli',
      const Duration(minutes: 1): 'za minutu',
      const Duration(minutes: 3): 'za 3 minuty',
      const Duration(minutes: 5): 'za 5 minut',
      const Duration(hours: 1): 'za hodinu',
      const Duration(hours: 3): 'za 3 hodiny',
      const Duration(hours: 5): 'za 5 hodin',
    }.entries) {
      expect(
        PaymentDeadline.format(clock.add(entry.key), 'cs'),
        endsWith('(${entry.value})'),
      );
    }
  });

  test('past and exact-now deadlines have no duplicate relative state', () {
    for (final deadline in [clock, clock.subtract(const Duration(days: 3))]) {
      expect(
        PaymentDeadline.format(deadline, 'cs'),
        LocaleDateTime.instant(deadline, 'cs'),
      );
    }
  });

  test(
    'injected clock controls future state without changing the exact date',
    () {
      final deadline = clock.add(const Duration(days: 3));
      final exact = LocaleDateTime.instant(deadline, 'cs');
      expect(PaymentDeadline.format(deadline, 'cs'), '$exact (za 3 dny)');
      TimeHelper.currentTime = deadline;
      expect(PaymentDeadline.format(deadline, 'cs'), exact);
    },
  );

  test('regional locale and UTC offset preserve the same instant', () {
    final deadline = clock.add(const Duration(days: 3));
    const offset = '2026-11-05T13:00:00+01:00';
    expect(
      PaymentDeadline.format(offset, 'cs_CZ'),
      PaymentDeadline.format(deadline, 'cs_CZ'),
    );
    expect(PaymentDeadline.format(offset, 'cs_CZ'), endsWith('(za 3 dny)'));
  });

  test(
    'invalid values and unsupported language retain original exact display',
    () {
      expect(PaymentDeadline.format(null, 'cs'), '');
      expect(PaymentDeadline.format('On site', 'cs'), 'On site');
      final future = clock.add(const Duration(days: 3));
      expect(
        PaymentDeadline.format(future, 'fr'),
        LocaleDateTime.instant(future, 'fr'),
      );
    },
  );
}
