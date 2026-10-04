import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/theme_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/timeline/light_timeline_view.dart';
import 'package:fstapp/components/timeline/advanced_timeline_view.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

TimeBlockItem _eventOn(DateTime date) => TimeBlockItem(
      id: date.day,
      startTime: DateTime(date.year, date.month, date.day, 10),
      endTime: DateTime(date.year, date.month, date.day, 11),
      timeBlockType: TimeBlockType.noAction,
      title: 'Event ${date.day}',
    );

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

Widget _testApp(List<TimeBlockItem> events, int occasionId,
        {bool advanced = false, ThemeData? theme}) =>
    EasyLocalization(
      supportedLocales: const [Locale('cs')],
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      fallbackLocale: const Locale('cs'),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: theme ?? ThemeConfig.theme(),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(
            body: advanced
                ? DefaultTabController(
                    length: events.length,
                    child: AdvancedTimelineView(
                      weekdays: const [
                        'PO',
                        'ÚT',
                        'ST',
                        'ČT',
                        'PÁ',
                        'SO',
                        'NE'
                      ],
                      groups: [
                        for (final event in events)
                          TimeBlockGroup(
                            title: event.title,
                            events: [event],
                            dateTime: event.startTime,
                          )
                      ],
                    ),
                  )
                : LightTimelineView(
                    events: events,
                    sessionOccasionId: occasionId,
                  ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    final loader = FontLoader(ThemeConfig.fontFamily)
      ..addFont(rootBundle.load('fonts/Futura PT Book.ttf'));
    await loader.load();
    SharedPreferences.setMockInitialValues({});
    timezone_data.initializeTimeZones();
    timezone.setLocalLocation(timezone.getLocation('Europe/Prague'));
    await EasyLocalization.ensureInitialized();
  });

  testWidgets(
      'day header matches Material 2 dimensions without an added divider',
      (tester) async {
    final events =
        List.generate(3, (index) => _eventOn(DateTime(2026, 12, 12 + index)));
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(_testApp(events, 91023,
          advanced: true,
          theme: ThemeData(
              useMaterial3: false,
              brightness: brightness,
              fontFamily: ThemeConfig.fontFamily)));
      await tester.pumpAndSettle();
      final previousBar = tester.getSize(find.byType(TabBar));
      final previousWeekday = tester.getSize(find.text('SO'));
      final previousDate = tester.getSize(find.text('12. 12.'));
      await tester.pumpWidget(_testApp(events, 91023,
          advanced: true, theme: ThemeConfig.theme(brightness: brightness)));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(TabBar)), previousBar);
      expect(tester.getSize(find.text('SO')), previousWeekday);
      expect(tester.getSize(find.text('12. 12.')), previousDate);
      final context = tester.element(find.byType(TabBar));
      expect(TabBarTheme.of(context).dividerHeight, 0);
      expect(TabBarTheme.of(context).dividerColor, Colors.transparent);
    }
  });

  for (final advanced in [false, true]) {
    testWidgets(
        '${advanced ? "advanced" : "light"} day tabs are centered on desktop and scroll on narrow screens',
        (tester) async {
      TimeHelper.currentTime = DateTime(2026, 10, 3, 12);
      addTearDown(() => TimeHelper.currentTime = null);
      final events =
          List.generate(3, (index) => _eventOn(DateTime(2026, 12, 12 + index)));
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 700);
      await tester.pumpWidget(_testApp(events, 91020, advanced: advanced));
      await tester.pumpAndSettle();
      final bar = tester.widget<TabBar>(find.byType(TabBar));
      final first = tester.getRect(find.byWidget(bar.tabs.first));
      final last = tester.getRect(find.byWidget(bar.tabs.last));
      final center = tester.getRect(find.byType(TabBar)).center.dx;
      expect((first.left + last.right) / 2, closeTo(center, 1));
      tester.view.physicalSize = const Size(320, 700);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      final controller =
          DefaultTabController.of(tester.element(find.byType(TabBar)));
      expect(controller.index, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('light Program opens on the current weekday at app startup',
      (tester) async {
    TimeHelper.currentTime = DateTime(2026, 8, 9, 12); // Sunday.
    addTearDown(() => TimeHelper.currentTime = null);
    final events = List.generate(
      6,
      (index) => _eventOn(DateTime(2026, 8, 11 + index)), // Tuesday–Sunday.
    );

    await tester.pumpWidget(_testApp(events, 91001));
    await tester.pumpAndSettle();

    final controller = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    expect(controller.index, 5);
  });

  testWidgets('light Program remembers a manual day only in process memory',
      (tester) async {
    TimeHelper.currentTime = DateTime(2026, 8, 9, 12); // Sunday.
    addTearDown(() => TimeHelper.currentTime = null);
    final events = List.generate(
      6,
      (index) => _eventOn(DateTime(2026, 8, 11 + index)),
    );

    await tester.pumpWidget(_testApp(events, 91002));
    await tester.pumpAndSettle();
    var controller = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    controller.animateTo(2);
    await tester.pumpAndSettle();
    expect(controller.index, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_testApp(events, 91002));
    await tester.pumpAndSettle();
    controller = DefaultTabController.of(
      tester.element(find.byType(TabBarView)),
    );
    expect(controller.index, 2);
  });

  testWidgets('light Program recalculates after a provisional partial dataset',
      (tester) async {
    TimeHelper.currentTime = DateTime(2026, 8, 9, 12); // Sunday.
    addTearDown(() => TimeHelper.currentTime = null);
    final completeEvents = List.generate(
      6,
      (index) => _eventOn(DateTime(2026, 8, 11 + index)),
    );

    await tester.pumpWidget(_testApp(completeEvents.take(1).toList(), 91003));
    await tester.pumpAndSettle();
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
      0,
    );

    await tester.pumpWidget(_testApp(completeEvents, 91003));
    await tester.pumpAndSettle();
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBarView))).index,
      5,
    );
  });
}
