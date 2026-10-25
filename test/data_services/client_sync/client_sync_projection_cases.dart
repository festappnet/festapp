import 'package:festapp_core/program.dart' as occasion_time;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:festapp_core/map.dart';
import 'package:timezone/timezone.dart' as timezone;

void main() {
  setUpAll(() {
    occasion_time.OccasionTimeContext.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Europe/Prague'));
  });

  test('event projection hydrates a saved event place from the map catalog',
      () {
    final events = ClientSyncProjection.projectEvents(
      catalog: {
        'events': [
          {
            'id': 42,
            'title': 'Večerní program',
            'startTime': '2026-08-14T18:00:00Z',
            'endTime': '2026-08-14T19:00:00Z',
            'placeId': 7,
          },
        ],
      },
      map: {
        'places': [
          {
            'id': 7,
            'title': 'Hlavní hala',
            'description': null,
            'type': 'hall',
            'coordinates': null,
            'order': 1,
            'icon': null,
            'aggregateVersion': 3,
          },
        ],
      },
      live: const {},
      privateProgram: const {
        'saved': [42],
      },
    );

    expect(events.single.isInMySchedule, isTrue);
    expect(events.single.place?.id, 7);
    expect(events.single.place?.title, 'Hlavní hala');
  });

  test('news projection preserves legacy newest-first order and view counts',
      () {
    final news = ClientSyncProjection.projectNews(
      content: {
        'news': [
          {
            'id': 199,
            'message': 'Oldest',
            'createdAt': '2026-08-01T10:00:00Z',
            'aggregateVersion': 1,
          },
          {
            'id': 204,
            'message': 'Newest',
            'createdAt': '2026-08-03T10:00:00Z',
            'aggregateVersion': 2,
          },
          {
            'id': 202,
            'message': 'Middle',
            'createdAt': '2026-08-02T10:00:00Z',
            'aggregateVersion': 1,
          },
        ],
      },
      live: {
        'newsViews': [
          {'newsId': 199, 'views': 2041},
          {'newsId': 202, 'views': 1157},
          {'newsId': 204, 'views': 1145},
        ],
      },
      marker: [
        {'newsId': 202}
      ],
    );

    expect(news.map((item) => item.id), [204, 202, 199]);
    expect(news.map((item) => item.views), [1145, 1157, 2041]);
    expect(news.map((item) => item.isRead), [false, true, true]);
  });

  test('missing live news counts stay unavailable instead of becoming zero',
      () {
    final news = ClientSyncProjection.projectNews(
      content: {
        'news': [
          {
            'id': 204,
            'message': 'Newest',
            'createdAt': '2026-08-03T10:00:00Z',
            'aggregateVersion': 2,
          },
        ],
      },
      live: const {},
      marker: null,
    );

    expect(news.single.views, isNull);
  });

  test(
      'missing event occupancy stays unavailable but an authoritative zero remains zero',
      () {
    Map<String, dynamic> catalog() => {
          'events': [
            {
              'id': 42,
              'title': 'Workshop',
              'startTime': '2026-08-14T18:00:00Z',
              'endTime': '2026-08-14T19:00:00Z',
              'maxParticipants': 10,
            },
          ],
        };

    final missing = ClientSyncProjection.projectEvents(
      catalog: catalog(),
      map: const {},
      live: const {},
      privateProgram: null,
    ).single;
    final actualZero = ClientSyncProjection.projectEvents(
      catalog: catalog(),
      map: const {},
      live: const {
        'events': [
          {'eventId': 42, 'participantCount': 0, 'savedCount': 0},
        ],
      },
      privateProgram: null,
    ).single;

    expect(missing.currentParticipants, isNull);
    expect(missing.participantCapacityLabel, isNull);
    expect(actualZero.currentParticipants, 0);
    expect(actualZero.participantCapacityLabel, '0/10');
  });

  test('private-profile replacement fully adds and removes companions', () {
    final withCompanion = ClientSyncProjection.projectCompanions({
      'companions': [
        {
          'id': 'companion',
          'name': 'Ada',
          'surname': 'Lovelace',
          'group_title': 'DISK 19',
          'origin': 'admin_assigned',
          'can_owner_delete': false,
          'event_ids': [42],
        },
      ],
    });
    final withoutCompanion =
        ClientSyncProjection.projectCompanions({'companions': []});

    expect(withCompanion.single.fullName, 'Ada Lovelace');
    expect(withCompanion.single.groupTitle, 'DISK 19');
    expect(withCompanion.single.canOwnerDelete, isFalse);
    expect(withoutCompanion, isEmpty,
        reason: 'an empty full replacement cannot retain the prior relation');
  });

  test('normal participant services resolve companion accommodation', () {
    final place = ClientSyncProjection.projectAccommodationPlace(
      userServices: const {
        'accommodation': {'room-a': 'paid'},
      },
      occasionServices: const {
        'accommodation': [
          {
            'code': 'room-a',
            'title': 'Fallback room title',
            'reference': 73,
          },
        ],
      },
      places: [PlaceModel(id: 73, title: 'Domov mládeže A')],
    );

    expect(place?.id, 73);
    expect(place?.title, 'Domov mládeže A');
  });
}
