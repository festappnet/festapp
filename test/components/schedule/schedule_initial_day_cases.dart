import 'dart:convert';

import 'package:fstapp/app_config.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_model.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:fstapp/widgets/dependency_material_bridge.dart';

import '../../support/fixtures/localization_log_fixture.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimeBlockItem event(DateTime start, DateTime end) => TimeBlockItem(
  id: start.millisecondsSinceEpoch,
  startTime: start,
  endTime: end,
  timeBlockType: TimeBlockType.noAction,
);

TimeBlockGroup day(DateTime date, {List<TimeBlockItem> events = const []}) =>
    TimeBlockGroup(title: '', dateTime: date, events: events);

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

void main() {
  // _EmptyAssetLoader intentionally supplies an empty Czech catalog.
  setUp(() {
    final logs = LocalizationLogFixture.install(expectedMissingCatalog: true);
    addTearDown(logs.dispose);
  });
  final now = DateTime(2026, 8, 8, 12); // Saturday.

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('day splitting handles canonical events in arbitrary order', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('cs')],
        path: 'assets/translations',
        assetLoader: const _EmptyAssetLoader(),
        fallbackLocale: const Locale('cs'),
        child: Builder(
          builder: (outerContext) => MaterialApp(
            builder: DependencyMaterialBridge.builder,
            locale: outerContext.locale,
            supportedLocales: outerContext.supportedLocales,
            localizationsDelegates: [
              ...outerContext.localizationDelegates,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Builder(
              builder: (value) {
                context = value;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final groups = TimeBlockHelper.splitTimeBlocksByDate(
      [
        event(DateTime(2026, 6, 21, 9), DateTime(2026, 6, 21, 10)),
        event(DateTime(2026, 6, 18, 11), DateTime(2026, 6, 18, 12)),
        event(DateTime(2026, 6, 20, 7), DateTime(2026, 6, 20, 8)),
        event(DateTime(2026, 6, 19, 7), DateTime(2026, 6, 19, 8)),
      ],
      context,
      4,
    );

    expect(groups.map((group) => group.dateTime?.day), [18, 19, 20, 21]);

    // Preserve the established (04:00, next 04:00] program-day boundary.
    expect(AppConfig.daySplitHour, 4);
    final late = event(DateTime(2026, 8, 8, 23, 30), DateTime(2026, 8, 9, 1));
    final overnight = event(
      DateTime(2026, 8, 9, 0, 30),
      DateTime(2026, 8, 9, 2),
    );
    final cutoff = event(DateTime(2026, 8, 9, 4), DateTime(2026, 8, 9, 5));
    final nextDay = event(
      DateTime(2026, 8, 9, 4, 0, 1),
      DateTime(2026, 8, 9, 6),
    );
    final programDays = TimeBlockHelper.splitTimeBlocksByDate(
      [nextDay, overnight, late, cutoff],
      context,
      AppConfig.daySplitHour,
    );
    expect(programDays.map((day) => day.dateTime!.day), [8, 9]);
    expect(programDays.first.events, [late, overnight, cutoff]);
    expect(programDays.last.events, [nextDay]);
    final morning = event(DateTime(2026, 8, 8, 9), DateTime(2026, 8, 8, 10));
    final periods = TimeBlockHelper.splitTimeBlocksByTimeOfDay([
      morning,
      late,
      overnight,
    ]);
    expect(periods.first.events, [morning]);
    expect(periods.last.events, [late, overnight]);
  });

  test('opens the exact current date when it exists', () {
    final groups = [
      day(DateTime(2026, 8, 7)),
      day(DateTime(2026, 8, 8)),
      day(DateTime(2026, 8, 9)),
    ];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 1);
  });

  test('restores legacy weekday selection for a program from another year', () {
    final groups = [
      day(DateTime(2025, 8, 8)), // Friday.
      day(DateTime(2025, 8, 9)), // Saturday.
      day(DateTime(2025, 8, 10)), // Sunday.
    ];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 1);
  });

  test('weekday selection also applies before an upcoming program', () {
    final groups = [
      day(DateTime(2026, 8, 14)), // Friday in the following week.
      day(DateTime(2026, 8, 15)), // Saturday in the following week.
      day(DateTime(2026, 8, 16)),
    ];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 1);
  });

  test('uses the first event weekday when a group has no explicit date', () {
    final groups = [
      TimeBlockGroup(
        title: '',
        events: [event(DateTime(2025, 8, 8, 10), DateTime(2025, 8, 8, 11))],
      ),
      TimeBlockGroup(
        title: '',
        events: [event(DateTime(2025, 8, 9, 10), DateTime(2025, 8, 9, 11))],
      ),
    ];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 1);
  });

  test('a currently running item has priority over date fallbacks', () {
    final groups = [
      day(DateTime(2025, 8, 9)),
      day(
        DateTime(2025, 8, 10),
        events: [
          event(
            now.subtract(const Duration(minutes: 30)),
            now.add(const Duration(minutes: 30)),
          ),
        ],
      ),
    ];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 1);
  });

  test('falls back to the first day when no weekday matches', () {
    final groups = [day(DateTime(2025, 8, 4)), day(DateTime(2025, 8, 5))];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 0);
    expect(calculateScheduleInitialDayIndex(const [], now: now), 0);
  });

  test('session selection overrides automatic weekday until app restart', () {
    final selection = ScheduleDaySessionSelection();
    final groups = [
      day(DateTime(2026, 8, 7)),
      day(DateTime(2026, 8, 8)),
      day(DateTime(2026, 8, 9)),
    ];

    expect(
      selection.resolveInitialIndex(occasionId: 9, dayGroups: groups, now: now),
      1,
    );
    selection.remember(9, groups[2]);
    expect(
      selection.resolveInitialIndex(occasionId: 9, dayGroups: groups, now: now),
      2,
    );
    expect(
      ScheduleDaySessionSelection().resolveInitialIndex(
        occasionId: 9,
        dayGroups: groups,
        now: now,
      ),
      1,
      reason: 'a new process-level session recalculates today',
    );
  });

  test('automatic startup day stays stable when reopening Program', () {
    final selection = ScheduleDaySessionSelection();
    final groups = [
      day(DateTime(2026, 8, 7)),
      day(DateTime(2026, 8, 8)),
      day(DateTime(2026, 8, 9)),
    ];

    expect(
      selection.resolveInitialIndex(occasionId: 9, dayGroups: groups, now: now),
      1,
    );
    expect(
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: groups,
        now: DateTime(2026, 8, 9, 12),
      ),
      1,
      reason: 'the automatic choice runs once per app session',
    );
  });

  test('session selection is isolated per occasion', () {
    final selection = ScheduleDaySessionSelection();
    final groups = [
      day(DateTime(2026, 8, 7)),
      day(DateTime(2026, 8, 8)),
      day(DateTime(2026, 8, 9)),
    ];
    selection.remember(9, groups[2]);

    expect(
      selection.resolveInitialIndex(occasionId: 9, dayGroups: groups, now: now),
      2,
    );
    expect(
      selection.resolveInitialIndex(
        occasionId: 10,
        dayGroups: groups,
        now: now,
      ),
      1,
    );
  });

  test('partial reload does not overwrite a remembered manual day', () {
    final selection = ScheduleDaySessionSelection();
    final completeGroups = [
      day(DateTime(2026, 8, 7)),
      day(DateTime(2026, 8, 8)),
      day(DateTime(2026, 8, 9)),
    ];
    selection.remember(9, completeGroups[2]);

    expect(
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: completeGroups.take(2).toList(),
        now: now,
      ),
      1,
      reason: 'the incomplete snapshot still needs a visible safe day',
    );
    expect(
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: completeGroups,
        now: now,
      ),
      2,
      reason: 'the complete snapshot restores the manual choice',
    );
  });

  test(
    'provisional first dataset does not lock Tuesday before Sunday arrives',
    () {
      final selection = ScheduleDaySessionSelection();
      final sunday = DateTime(2026, 8, 9, 12);
      final partialGroups = [day(DateTime(2026, 8, 4))]; // Tuesday only.
      final completeGroups = [
        day(DateTime(2026, 8, 4)),
        day(DateTime(2026, 8, 5)),
        day(DateTime(2026, 8, 6)),
        day(DateTime(2026, 8, 7)),
        day(DateTime(2026, 8, 8)),
        day(DateTime(2026, 8, 9)),
      ];

      expect(
        selection.resolveInitialIndex(
          occasionId: 9,
          dayGroups: partialGroups,
          now: sunday,
        ),
        0,
      );
      expect(
        selection.resolveInitialIndex(
          occasionId: 9,
          dayGroups: completeGroups,
          now: sunday,
        ),
        5,
        reason: 'the first incomplete projection must not become a user choice',
      );
    },
  );

  group('existing timezone compatibility', () {
    late tz.Location previousZone;
    DateTime? previousClock;
    setUp(() async {
      if (tz.timeZoneDatabase.locations.isEmpty) {
        await TimeHelper.initializeTimeZone();
      }
      previousZone = tz.local;
      previousClock = TimeHelper.currentTime;
    });
    tearDown(() {
      tz.setLocalLocation(previousZone);
      TimeHelper.currentTime = previousClock;
    });

    test('canonical embedded initialization retains saved aliases', () async {
      await TimeHelper.initializeTimeZone();
      for (final name in [
        'Europe/Prague',
        'America/New_York',
        'Asia/Kathmandu',
        'UTC',
        'Europe/Bratislava',
      ]) {
        TimeHelper.setTimeZoneLocation(name);
        expect(TimeHelper.eventTime.location.name, name);
        expect(TimeHelper.getAvailableTimezoneNames(), contains(name));
      }
      expect(
        () => DateTime.utc(2026).toOccasionTime('Invalid/Timezone'),
        throwsA(isA<tz.LocationNotFoundException>()),
      );
    });

    test(
      'existing cached timezone and fallback survive occasion switches',
      () async {
        await TimeHelper.initializeTimeZone();
        for (final name in [
          'Asia/Kathmandu',
          'America/New_York',
          'Europe/Prague',
          'UTC',
          'Etc/UTC',
          'GMT',
          'Europe/Bratislava',
          'US/Eastern',
        ]) {
          final cached = OccasionSettingsModel.fromJson({
            'data': {'timezone': name},
          });
          TimeHelper.setTimeZoneLocation(cached.data!['timezone']);
          expect(tz.local.name, name);
        }
        for (final name in <String?>[null, '', 'Invalid/Timezone']) {
          TimeHelper.setTimeZoneLocation(name);
          expect(tz.local.name, 'Europe/Prague');
        }
      },
    );

    test('offline settings serialization preserves existing timezone and custom data', () async {
      await TimeHelper.initializeTimeZone();
      final original = <String, dynamic>{
        'timezone': 'Asia/Kathmandu',
        'existing_custom_setting': {'keep': true},
        'game': {'custom_rule': 7},
      };
      final settings = OccasionSettingsModel.fromJson({'data': original});
      final restored = OccasionSettingsModel.fromJson(
        jsonDecode(jsonEncode(settings)) as Map<String, dynamic>,
      );
      expect(restored.data!['timezone'], 'Asia/Kathmandu');
      expect(restored.data!['existing_custom_setting'], {'keep': true});
      expect((restored.data!['game'] as Map)['custom_rule'], 7);
      expect(original, {
        'timezone': 'Asia/Kathmandu',
        'existing_custom_setting': {'keep': true},
        'game': {'custom_rule': 7},
      });
      TimeHelper.setTimeZoneLocation(restored.data!['timezone']);
      expect(tz.local.name, 'Asia/Kathmandu');
    });

    test(
      'UTC instants and entered wall times keep distinct conversion rules',
      () async {
        await TimeHelper.initializeTimeZone();
        final instant = DateTime.utc(2026, 8, 8, 23, 30, 14, 123, 456);
        for (final name in [
          'Europe/Prague',
          'America/New_York',
          'Asia/Kathmandu',
        ]) {
          TimeHelper.setTimeZoneLocation(name);
          final local = instant.toOccasionTime();
          expect(local.toUtcFromOccasionTime(), instant);
          final wall = DateTime(
            local.year,
            local.month,
            local.day,
            local.hour,
            local.minute,
            local.second,
            local.millisecond,
            local.microsecond,
          );
          expect(wall.toUtcFromOccasionTime(), instant);
          expect(instant.toUtcFromOccasionTime(), instant);
        }
        TimeHelper.setTimeZoneLocation('Asia/Kathmandu');
        final local = instant.toOccasionTime();
        expect([local.day, local.hour, local.minute], [9, 5, 15]);
        final alreadyZoned = instant.toOccasionTime('America/New_York');
        expect(alreadyZoned.toOccasionTime().toUtc(), instant);
      },
    );

    test('time travel follows the selected occasion zone without changing the instant', () async {
      await TimeHelper.initializeTimeZone();
      final instant = DateTime.utc(2026, 8, 8, 23, 30);
      TimeHelper.currentTime = instant;
      TimeHelper.setTimeZoneLocation('Europe/Prague');
      expect([TimeHelper.now().day, TimeHelper.now().hour], [9, 1]);
      TimeHelper.setTimeZoneLocation('America/New_York');
      expect([TimeHelper.now().day, TimeHelper.now().hour], [8, 19]);
      expect(TimeHelper.now().toUtc(), instant);
    });

    test('occasion JSON keeps its explicit zone and exact UTC values across midnight', () async {
      await TimeHelper.initializeTimeZone();
      TimeHelper.setTimeZoneLocation('America/New_York');
      final occasion = OccasionModel.fromJson({
        'id': 1,
        'is_open': true,
        'is_hidden': false,
        'is_promoted': false,
        'start_time': '2026-08-08T23:30:00Z',
        'end_time': '2026-08-09T01:30:00Z',
        'data': {'timezone': 'Europe/Prague', 'existing_custom_setting': true},
      });
      expect([occasion.startTime!.day, occasion.startTime!.hour], [9, 1]);
      final saved = occasion.toJson();
      expect(saved['start_time'], '2026-08-08T23:30:00.000Z');
      expect(saved['end_time'], '2026-08-09T01:30:00.000Z');
      expect(saved['data'], {
        'timezone': 'Europe/Prague',
        'existing_custom_setting': true,
      });
    });

    test(
      'DST transitions preserve both repeated instants and elapsed duration',
      () async {
        await TimeHelper.initializeTimeZone();
        TimeHelper.setTimeZoneLocation('Europe/Prague');
        final springBefore = DateTime.utc(2026, 3, 29, 0, 30).toOccasionTime();
        final springAfter = DateTime.utc(2026, 3, 29, 1, 30).toOccasionTime();
        expect([springBefore.hour, springAfter.hour], [1, 3]);
        expect(TimeHelper.differenceInHours(springBefore, springAfter), 1);
        final first = DateTime.utc(2026, 10, 25, 0, 30).toOccasionTime();
        final second = DateTime.utc(2026, 10, 25, 1, 30).toOccasionTime();
        expect(
          [first.hour, first.minute, second.hour, second.minute],
          [2, 30, 2, 30],
        );
        expect(
          first.toUtcFromOccasionTime(),
          DateTime.utc(2026, 10, 25, 0, 30),
        );
        expect(
          second.toUtcFromOccasionTime(),
          DateTime.utc(2026, 10, 25, 1, 30),
        );
        expect(first.roundDown().toUtc(), DateTime.utc(2026, 10, 25));
        expect(second.roundDown().toUtc(), DateTime.utc(2026, 10, 25, 1));
      },
    );
  });
}
