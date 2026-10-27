import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fstapp/components/notification_center/notification_center_time.dart';

import '../../support/fixtures/widget_environment_fixture.dart';

void main() {
  WidgetEnvironmentFixture.register();
  testWidgets(
    'Czech calendar labels, year boundary and exact local timestamps',
    (tester) async {
      await initializeDateFormatting('cs');
      final env = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations: jsonDecode(
          File('assets/translations/cs.json').readAsStringSync(),
        ),
      );
      await env.pumpWidget(tester, const SizedBox.shrink());
      final now = DateTime(2026, 1, 1, 0, 5);
      expect(
        NotificationCenterTime.timestamp(
          DateTime(2026, 1, 1, 0, 1),
          'cs',
          now: now,
        ),
        'Dnes v 0:01',
      );
      // Yesterday means the previous calendar day, even only minutes after midnight.
      expect(
        NotificationCenterTime.timestamp(
          DateTime(2025, 12, 31, 23, 59),
          'cs',
          now: now,
        ),
        'Včera v 23:59',
      );
      expect(
        NotificationCenterTime.timestamp(
          DateTime(2025, 10, 23, 16, 30),
          'cs',
          now: now,
        ),
        '23. 10. 2025 v 16:30',
      );
      expect(
        NotificationCenterTime.day(DateTime(2026, 1, 2), 'cs', now: now),
        '2. 1. 2026',
      );
      expect(
        NotificationCenterTime.dayHeading(
          DateTime(2025, 12, 27),
          'cs',
          now: now,
        ),
        'Před 5 dny',
      );
      expect(
        NotificationCenterTime.dayHeading(
          DateTime(2025, 12, 29),
          'cs',
          now: now,
        ),
        'Před 3 dny',
      );
      expect(
        NotificationCenterTime.dayHeading(
          DateTime(2025, 12, 25),
          'cs',
          now: now,
        ),
        '25. 12. 2025',
      );
      // Incoming instants convert to the device zone once; exact time retains the year.
      final local = DateTime(2026, 1, 1, 0, 1);
      expect(
        NotificationCenterTime.timestamp(local.toUtc(), 'cs', now: now),
        'Dnes v 0:01',
      );
      expect(
        NotificationCenterTime.exact(local.toUtc(), 'cs'),
        '1. 1. 2026 0:01',
      );
      expect(
        NotificationCenterTime.day(DateTime(2025, 12, 31), 'cs', now: now),
        'Včera',
      );
    },
  );
}
