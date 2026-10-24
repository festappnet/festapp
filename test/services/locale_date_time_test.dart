import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Test-only delegates already supplied by the localization SDK.
// ignore: depend_on_referenced_packages
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fstapp/services/locale_date_time.dart';
import 'package:fstapp/components/email_delivery/email_delivery_indicator.dart';
import '../support/fixtures/localization_log_fixture.dart';

void main() {
  setUpAll(() => initializeDateFormatting());
  setUp(() {
    final oldLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'en_US';
    addTearDown(() => Intl.defaultLocale = oldLocale);
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  const dates = {
    'cs': '23. 10. 2026',
    'sk': '23. 10. 2026',
    'en': '10/23/2026',
    'de': '23.10.2026',
    'pl': '23.10.2026',
    'uk': '23.10.2026',
  };
  for (final entry in dates.entries) {
    test(
        'grid date display follows ${entry.key} and preserves canonical values',
        () {
      const raw = '2026-10-23';
      expect(LocaleDateTime.dateCell(raw, entry.key), entry.value);
      expect(raw, '2026-10-23');
      expect(LocaleDateTime.dateCell('', entry.key), '');
      expect(LocaleDateTime.dateCell('On site', entry.key), 'On site');
      expect(LocaleDateTime.dateCell(null, entry.key), '');
    });
  }
  test('time uses the locale hour cycle and timestamps convert instants once',
      () {
    expect(LocaleDateTime.timeCell('18:30', 'cs'), '18:30');
    expect(LocaleDateTime.timeCell('18:30', 'en'), contains('6:30'));
    expect(LocaleDateTime.timeCell('18:30', 'en'), contains('PM'));
    expect(
        LocaleDateTime.dateTimeCell('2026-10-23 18:30:24', 'cs', seconds: true),
        '23. 10. 2026 18:30:24');
    final local = DateTime(2026, 10, 23, 18, 30);
    expect(LocaleDateTime.instant(local.toUtc().toIso8601String(), 'cs'),
        '23. 10. 2026 18:30');
  });
  testWidgets(
      'Czech delivery tooltip and explanation ignore an English Intl default',
      (tester) async {
    final local = DateTime(2026, 10, 23, 18, 30);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('cs'),
      supportedLocales: const [Locale('cs')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(
          body: EmailDeliveryIndicator(summary: {
        'state': 'bounce',
        'kind': 'order_confirmation',
        'loaded_at': local.toUtc().toIso8601String(),
        'messages': [
          {
            'state': 'bounce',
            'kind': 'order_confirmation',
            'at': local.toUtc().toIso8601String()
          }
        ],
      })),
    ));
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, contains('23. 10. 2026 18:30'));
    expect(tooltip.message, isNot(contains('10/23/2026')));
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('23. 10. 2026 18:30'), findsOneWidget);
  });
}
