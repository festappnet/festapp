import 'package:festapp_core/program.dart' as occasion_time;
import 'package:festapp_core/map.dart';
import 'package:festapp_core/program.dart';
import 'package:test/test.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  late OccasionTimeContext prague;
  setUpAll(() {
    occasion_time.OccasionTimeContext.initializeTimeZones();
    prague = OccasionTimeContext(tz.getLocation('Europe/Prague'));
  });

  test(
    'event wire codec preserves unknown metadata without mutating inputs',
    () {
      final source = <String, dynamic>{
        'id': 7,
        'aggregate_version': 12,
        'start_time': '2026-08-08T22:30:00Z',
        'end_time': '2026-08-08T23:30:00Z',
        'data': {
          'unknown': [
            1,
            {'key': 'value'},
          ],
        },
        'childEvents': [9, 8],
        'place': 3,
      };
      final event = EventModel.fromJson(source, timeContext: prague);
      expect(event.title, isNull);
      expect(event.aggregateVersion, 12);
      expect(event.startTime.day, 9);
      expect(event.startTime.hour, 0);
      expect(event.toJson()['start_time'], '2026-08-08T22:30:00.000Z');
      expect(event.toJson()['childEvents'], [9, 8]);
      expect(event.toUpsertMap()['place'], 3);
      expect((source['data'] as Map).containsKey('is_cancelled'), isFalse);
      (source['data']['unknown'] as List).clear();
      expect(event.data!['unknown'], [
        1,
        {'key': 'value'},
      ]);
      expect(() => event.data!['unknown'].clear(), throwsUnsupportedError);
      final edited = event.copyWith(title: 'Changed', place: null, data: null);
      expect(edited.place, isNull);
      expect(edited.data, isNull);
      expect(event.place!.id, 3);
      expect(edited.timeContext, same(prague));
      expect(event.childEventIds, [9, 8]);
    },
  );

  test(
    'missing null and empty event metadata retain existing wire defaults',
    () {
      for (final json in <Map<String, dynamic>>[
        {},
        {'data': null},
        {'data': {}},
      ]) {
        final event = EventModel.fromJson(json, timeContext: prague);
        expect(event.title, isNull);
        expect(event.isCancelled, isFalse);
        expect(event.toJson()['data'], {'is_cancelled': false});
        expect(event.toUpsertMap()['title'], isNull);
      }
    },
  );

  test('occasion time preserves instants and wall components across DST', () {
    final before = prague.toOccasionTime(
      DateTime.parse('2026-03-29T00:30:00Z'),
    );
    final after = prague.toOccasionTime(DateTime.parse('2026-03-29T01:30:00Z'));
    expect(before.hour, 1);
    expect(after.hour, 3);
    expect(after.difference(before), const Duration(hours: 1));
    expect(
      prague.toUtc(DateTime(2026, 8, 9, 0, 30)),
      DateTime.utc(2026, 8, 8, 22, 30),
    );
    final first = DateTime.parse('2026-10-25T00:30:00Z');
    final second = DateTime.parse('2026-10-25T01:30:00Z');
    expect(prague.toOccasionTime(first).hour, 2);
    expect(prague.toOccasionTime(second).hour, 2);
    expect(prague.toUtc(prague.toOccasionTime(first)), first);
    expect(prague.toUtc(prague.toOccasionTime(second)), second);
  });

  test('child projection retains source order IDs and bounded cycle edges', () {
    EventModel event(int id, List<int> children) => EventModel(
      id: id,
      timeContext: prague,
      startTime: DateTime(2026),
      endTime: DateTime(2026),
      childEventIds: children,
    );
    final original = [
      event(1, [3, 2, 99]),
      event(2, [1]),
      event(3, []),
    ];
    final linked = attachEventChildren(original, {
      for (final event in original) event.id!: event.childEventIds!,
    });
    expect(linked.map((e) => e.id), [1, 2, 3]);
    expect(linked.first.childEvents.map((e) => e.id), [3, 2]);
    expect(linked.first.childEventIds, [3, 2, 99]);
    expect(linked.first.childEvents.last.childEvents.single.id, 1);
    expect(original.first.childEvents, isEmpty);
    expect(() => linked.first.childEvents.clear(), throwsUnsupportedError);
  });

  test('place coordinates are owned and nullable fields can be cleared', () {
    final coordinates = {'lat': 49.0, 'lng': 18.0};
    final place = PlaceModel.fromJson({
      'id': 3,
      'title': 'Hall',
      'aggregate_version': 4,
      'coordinates': {'latLng': coordinates},
    });
    coordinates['lat'] = 0;
    expect(place.getLat(), 49);
    expect(place.aggregateVersion, 4);
    expect(place.copyWith(title: null, latLng: null).hasCoordinates, isFalse);
    expect(place.copyWith(title: null).title, isNull);
    expect(place.title, 'Hall');
    expect(place.toJson()['coordinates'], {
      'latLng': {'lat': 49.0, 'lng': 18.0},
    });
    expect(() => place.latLng['lat'] = 0, throwsUnsupportedError);
  });
}
