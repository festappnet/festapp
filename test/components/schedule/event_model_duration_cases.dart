import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('cs'));

  test('compact event duration uses two-letter uppercase weekday', () {
    final event = EventModel(
      startTime: DateTime(2026, 8, 8, 14, 30),
      endTime: DateTime(2026, 8, 8, 16),
    );

    expect(
      event.durationCompactStringForLocale('cs'),
      'SO 8. 8. 14:30 - 16:00',
    );
  });
}
