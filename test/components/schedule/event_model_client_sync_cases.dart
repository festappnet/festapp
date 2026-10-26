import 'package:festapp_core/program.dart' as occasion_time;
import 'package:fstapp/services/time_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:festapp_core/program.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(() {
    occasion_time.OccasionTimeContext.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Europe/Prague'));
  });

  test('editor DTO preserves both sides of event-group navigation', () {
    final event = EventModel.fromCommandJson({
      'id': 2933,
      'title': 'Parent event',
      'startTime': '2026-08-11T14:00:00Z',
      'endTime': '2026-08-11T16:00:00Z',
      'parentEventIds': [100],
      'childEventIds': [2608, 2609],
      'eventRoleIds': <int>[],
    }, 7, timeContext: TimeHelper.eventTime);

    expect(event.parentEventIds, [100]);
    expect(event.childEventIds, [2608, 2609]);
    expect(event.aggregateVersion, 7);
  });

  test('editor DTO with no assigned place keeps place null', () {
    final event = EventModel.fromCommandJson({
      'id': 2933,
      'title': 'Event without a place',
      'startTime': '2026-08-11T14:00:00Z',
      'endTime': '2026-08-11T16:00:00Z',
      'placeId': null,
    }, 7, timeContext: TimeHelper.eventTime);

    expect(event.place, isNull);
  });
}
