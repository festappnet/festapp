import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/navigation/routed_day_tabs.dart';
import 'package:fstapp/router_service.dart';

Iterable<RouteMatch> flatten(List<RouteMatch> routes) sync* {
  for (final route in routes) {
    yield route;
    yield* flatten(route.children ?? []);
  }
}

void main() {
  final paths = <String, String>{
    'admin/info/information': 'InformationInformationRoute',
    'admin/info/songbook': 'InformationSongbookRoute',
    'admin/events/schedule': 'ScheduleScheduleRoute',
    'admin/events/suspicious': 'ScheduleSuspiciousRoute',
    'admin/events/exclusivity': 'ScheduleExclusivityRoute',
    'admin/events/feedback': 'ScheduleFeedbackRoute',
    'admin/places/list': 'PlacesListRoute',
    'admin/places/paths': 'PlacesPathsRoute',
    'admin/places/types': 'PlacesTypesRoute',
    'admin/places/icons': 'PlacesIconsRoute',
    'admin/game/checkpoints': 'GameCheckpointsRoute',
    'admin/game/groups': 'GameGroupsRoute',
    'admin/game/settings': 'GameSettingsRoute',
    'reservations/orders/current': 'OrdersCurrentRoute',
    'reservations/orders/history': 'OrdersHistoryRoute',
    'reservations/forms': 'FormsListRoute',
    'reservations/forms/second-form/editor': 'FormEditorRoute',
    'reservations/forms/second-form/settings': 'FormSettingsRoute',
    'reservations/forms/second-form/design': 'FormDesignRoute',
    'reservations/forms/second-form/responses': 'FormResponsesRoute',
    'reservations/inventory-pools': 'InventoryPoolsListRoute',
    'reservations/inventory-pools/42/occupancy': 'InventoryPoolOccupancyRoute',
    'reservations/inventory-pools/42/rooms': 'InventoryPoolRoomsRoute',
    'reservations/inventory-pools/42/settings': 'InventoryPoolSettingsRoute',
    for (final section in [
      'speakers',
      'groups',
      'services',
      'volunteers',
      'users',
      'email-templates',
      'email-delivery',
      'changes',
      'settings'
    ])
      'admin/$section': '${{
            'services': 'Service',
            'email-templates': 'EmailTemplates',
            'email-delivery': 'EmailDelivery'
          }[section] ?? '${section[0].toUpperCase()}${section.substring(1)}'}SectionRoute',
    for (final section in [
      'tickets',
      'blueprint',
      'products',
      'report',
      'users',
      'email-templates',
      'email-delivery',
      'settings'
    ])
      'reservations/$section': '${{
            'email-templates': 'EmailTemplates',
            'email-delivery': 'EmailDelivery'
          }[section] ?? '${section[0].toUpperCase()}${section.substring(1)}'}SectionRoute',
  };
  for (final entry in paths.entries) {
    test('matches ${entry.key} with occasion identity and query', () {
      final router = AppRouter();
      final matches = router.matcher.match(
          '/event-a/${entry.key}?day=2026-10-03&preview-day=2026-10-04',
          includePrefixMatches: false)!;
      final routes = flatten(matches).toList();
      expect(routes.last.name, entry.value);
      expect(routes.first.params.getString(AppRouter.linkFormatted), 'event-a');
      expect(routes.last.queryParams.getString('day'), '2026-10-03');
      expect(routes.last.queryParams.getString('preview-day'), '2026-10-04');
    });
  }
  for (final section in [
    'occasions',
    'users',
    'quotes',
    'settings',
    'email-templates',
    'bank-accounts',
    'bank-accounts/9/general',
    'bank-accounts/9/connection',
    'bank-accounts/9/users'
  ]) {
    test('unit/$section stays under the unit context', () {
      final matches = AppRouter()
          .matcher
          .match('/unit/5/edit/$section', includePrefixMatches: false)!;
      final routes = flatten(matches).toList();
      expect(routes.first.name, 'UnitAdminRoute');
      expect(routes.first.params.getInt('id'), 5);
      expect(routes.last.name, isNot('NavigationNotFoundRoute'));
    });
  }
  for (final path in [
    '/event-a/admin/unknown',
    '/event-a/reservations/unknown',
    '/event-a/admin/events/unknown',
    '/event-a/reservations/forms/second-form/unknown',
    '/unit/5/edit/unknown'
  ]) {
    test('unknown slug is local: $path', () {
      expect(
          flatten(AppRouter().matcher.match(path, includePrefixMatches: false)!)
              .last
              .name,
          'NavigationNotFoundRoute');
    });
  }
  test('entry links include their canonical children', () {
    expect(flatten(AppRouter().matcher.match('/event-a/admin')!).last.name,
        'InformationInformationRoute');
    expect(
        flatten(AppRouter().matcher.match('/event-a/reservations')!).last.name,
        'OrdersCurrentRoute');
    expect(flatten(AppRouter().matcher.match('/unit/5/edit')!).last.name,
        'UnitOccasionsRoute');
  });
  test('dates use full calendar identity and reject invalid calendar days', () {
    final days = [
      DateTime(2026, 10, 17),
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 10)
    ];
    expect(DayRouteSelection.resolve(days, '2026-10-03', 0), 1);
    expect(DayRouteSelection.resolve(days, '2026-10-10', 0), 2);
    expect(DayRouteSelection.resolve(days, '2026-02-30', 1), 1);
    expect(DayRouteSelection.parse('2026-2-03'), isNull);
    expect(DayRouteSelection.parse('2026-02-30'), isNull);
  });
  test('login return accepts only internal administration URLs', () {
    expect(
        RouterService.isAdministrationReturnPath(
            '/event-a/reservations/forms/second/responses?day=2026-10-03'),
        isTrue);
    expect(
        RouterService.isAdministrationReturnPath(
            '/unit/5/edit/bank-accounts/9/users'),
        isTrue);
    expect(
        RouterService.isAdministrationReturnPath(
            'https://other.test/event-a/admin'),
        isFalse);
    expect(
        RouterService.isAdministrationReturnPath('//other.test/event-a/admin'),
        isFalse);
    expect(RouterService.isAdministrationReturnPath('/login'), isFalse);
  });
}
