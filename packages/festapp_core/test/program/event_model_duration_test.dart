import 'package:timezone/timezone.dart' as tz;
import 'package:test/test.dart';
import 'package:festapp_core/program.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  group('event_model_duration', () {
    setUpAll(() => initializeDateFormatting('cs'));

    test('compact event duration uses two-letter uppercase weekday', () {
      final event = EventModel(
        startTime: DateTime(2026, 8, 8, 14, 30),
        endTime: DateTime(2026, 8, 8, 16),
        timeContext: OccasionTimeContext(tz.UTC),
      );

      expect(
        event.durationCompactStringForLocale('cs'),
        'SO 8. 8. 14:30 - 16:00',
      );
    });
  });
}
