import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:fstapp/components/occasion/occasion_home_page.dart';

void main() {
  test('program tab initializes its nested schedule root', () {
    final source = File(
      'lib/components/occasion/occasion_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('ScheduleNavigationRoute(children: ['));
    expect(source, contains('_scheduleRootRoute()'));
    expect(source, contains('return const ScheduleRoute()'));
    expect(source, contains('return const ScheduleLightRoute()'));
    expect(source, contains('return const ScheduleBasicRoute()'));
  });

  test('program tab has a canonical root distinct from event detail', () {
    final router = AppRouter();
    final occasionRoutes = router.routeCollection
        .subCollectionOf(OccasionHomeRoute.name)
        .subCollectionOf(ScheduleNavigationRoute.name);
    final root = occasionRoutes.routes.singleWhere(
      (route) => route.path.isEmpty,
    );

    expect(root.name, isNot(EventRoute.name));
  });

  test('bottom navigation replaces the program stack with canonical root', () {
    final source = File(
      'lib/components/occasion/occasion_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('if (tabKey == OccasionTab.home)'));
    expect(source, contains('route.path.isEmpty'));
    expect(source, contains('stackRouter.replaceAll'));
    expect(source, contains('if (isReselected)'));
  });

  test('reselecting the map requests its canonical overview', () {
    final source = File(
      'lib/components/occasion/occasion_home_page.dart',
    ).readAsStringSync();

    expect(source, contains('key == OccasionTab.map'));
    expect(source, contains('_mapSession.resetToOverview()'));
    expect(source, contains('if (tabKey == OccasionTab.map)'));
    expect(source, contains('current.queryParams.optString(\'placeType\')'));
    expect(
      source,
      contains(
        'PublicMapRoute(destination: PublicMapPage.overviewDestination)',
      ),
    );
  });

  test('only tapping the already active bottom tab requests a root reset', () {
    expect(
      isBottomNavigationReselection(activeIndex: 1, selectedIndex: 0),
      isFalse,
    );
    expect(
      isBottomNavigationReselection(activeIndex: 0, selectedIndex: 0),
      isTrue,
    );
  });

  testWidgets('initial map tab visibility sync runs after the build phase',
      (tester) async {
    final session = PublicMapSession();

    await tester.pumpWidget(
      MaterialApp(
        home: PublicMapSessionScope(
          session: session,
          child: Column(
            children: [
              Builder(builder: (context) {
                PublicMapSessionScope.watch(context);
                return const SizedBox();
              }),
              Builder(builder: (context) {
                scheduleInitialMapTabVisibilitySync(
                  () => session.setVisible(true),
                );
                return const SizedBox();
              }),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(session.isMapVisible, isTrue);
    session.dispose();
  });

  test('program event details stay inside the retained occasion shell', () {
    const scheduleSources = [
      'lib/components/schedule/schedule_page.dart',
      'lib/components/schedule/schedule_basic_page.dart',
      'lib/components/schedule/schedule_light_page.dart',
      'lib/components/schedule/event_page.dart',
    ];

    for (final path in scheduleSources) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        matches(
          RegExp(r'context\.router\s*\.push\(EventRoute\(id: id\)\)'),
        ),
        reason: '$path must push into the nested program router',
      );
      expect(
        source,
        isNot(contains(
          r'RouterService.navigateOccasion(context, "${EventPage.ROUTE}/$id")',
        )),
        reason: '$path must not rebuild the occasion shell by absolute path',
      );
    }
  });

  test('event back navigation reconstructs the canonical program root', () {
    final source = File('lib/router_service.dart').readAsStringSync();
    final scheduleBack = RegExp(
      r'static void scheduleBack\(BuildContext context\) \{([\s\S]*?)\n  \}',
    ).firstMatch(source)?.group(1);

    expect(scheduleBack, isNotNull);
    expect(scheduleBack, contains('context.tabsRouter'));
    expect(scheduleBack, contains('stackRouterOfIndex'));
    expect(
      scheduleBack,
      contains('programRouter.routeCollection.routes.firstWhere'),
    );
    expect(scheduleBack, contains('route.path.isEmpty'));
    expect(
      scheduleBack,
      contains('programRouter.replaceAll'),
    );
    expect(
      scheduleBack,
      allOf(
        isNot(contains('maybePop')),
        isNot(contains('context.router.replacePath')),
      ),
      reason:
          'Popping the only nested EventRoute leaves the program router empty.',
    );
  });
}
