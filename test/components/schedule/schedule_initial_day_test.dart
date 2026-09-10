import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  final now = DateTime(2026, 8, 8, 12); // Saturday.

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('day splitting handles canonical events in arbitrary order',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      fallbackLocale: const Locale('cs'),
      child: Builder(
        builder: (outerContext) => MaterialApp(
          locale: outerContext.locale,
          supportedLocales: outerContext.supportedLocales,
          localizationsDelegates: outerContext.localizationDelegates,
          home: Builder(builder: (value) {
            context = value;
            return const SizedBox.shrink();
          }),
        ),
      ),
    ));
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
        events: [
          event(DateTime(2025, 8, 8, 10), DateTime(2025, 8, 8, 11)),
        ],
      ),
      TimeBlockGroup(
        title: '',
        events: [
          event(DateTime(2025, 8, 9, 10), DateTime(2025, 8, 9, 11)),
        ],
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
          event(now.subtract(const Duration(minutes: 30)),
              now.add(const Duration(minutes: 30)))
        ],
      ),
    ];

    expect(calculateScheduleInitialDayIndex(groups, now: now), 1);
  });

  test('falls back to the first day when no weekday matches', () {
    final groups = [
      day(DateTime(2025, 8, 4)),
      day(DateTime(2025, 8, 5)),
    ];

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
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: groups,
        now: now,
      ),
      1,
    );
    selection.remember(9, groups[2]);
    expect(
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: groups,
        now: now,
      ),
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
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: groups,
        now: now,
      ),
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
      selection.resolveInitialIndex(
        occasionId: 9,
        dayGroups: groups,
        now: now,
      ),
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

  test('provisional first dataset does not lock Tuesday before Sunday arrives',
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
  });
}
