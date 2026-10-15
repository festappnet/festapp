import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/app_router.dart';

Iterable<RouteMatch> flatten(List<RouteMatch> matches) sync* {
  for (final match in matches) {
    yield match;
    yield* flatten(match.children ?? const []);
  }
}

void main() {
  test('public occasion pages follow the compiled tenant capability', () {
    final router = AppRouter();
    for (final path in [
      '/demo',
      '/demo/event',
      '/demo/event/42',
      '/demo/news',
      '/demo/newsForm',
      '/demo/map/overview',
      '/demo/map/42',
      '/demo/user',
      '/demo/info',
      '/demo/timetable',
      '/demo/myschedule',
      '/demo/counseling',
      '/demo/game',
      '/demo/songbook',
      '/demo/userstay',
      '/map-editor',
      '/demo/eventEdit/42',
      '/demo/reception',
      '/demo/cleaning/42',
    ]) {
      final matches = router.matcher.match(path, includePrefixMatches: false);
      expect(matches, isNotNull, reason: path);
      final names = flatten(matches!).map((match) => match.name).toList();
      if (AppConfig.isAppSupported) {
        expect(names, isNot(contains('OrganizationRoute')), reason: path);
      } else {
        expect(names, ['OrganizationRoute'], reason: path);
      }
    }
  });

  test('content administration enters ticketing when the app is disabled', () {
    final router = AppRouter();
    for (final path in [
      '/demo/admin',
      '/demo/admin/info/information',
      '/demo/admin/volunteers',
      '/demo/admin/events/schedule',
    ]) {
      final matches = router.matcher.match(path, includePrefixMatches: false);
      expect(matches, isNotNull, reason: path);
      final names = flatten(matches!).map((match) => match.name).toList();
      expect(
          names,
          contains(
              AppConfig.isAppSupported ? 'AdminRoute' : 'ReservationsRoute'),
          reason: path);
      if (!AppConfig.isAppSupported) {
        expect(names, isNot(contains('AdminRoute')), reason: path);
        final target = flatten(matches)
            .firstWhere((match) => match.name == 'ReservationsRoute');
        expect(target.params.getString(AppRouter.linkFormatted), 'demo');
      }
    }
  });

  test('ticketing, administration and account routes remain available', () {
    final router = AppRouter();
    for (final entry in {
      '/login': 'LoginRoute',
      '/resetPassword?token=fixture': 'ResetPasswordRoute',
      '/unit/2/edit': 'UnitAdminRoute',
      '/demo/reservations': 'ReservationsRoute',
      '/demo/check/42': 'CheckRoute',
      '/form/demo': 'FormRoute',
    }.entries) {
      final matches =
          router.matcher.match(entry.key, includePrefixMatches: false);
      expect(matches, isNotNull, reason: entry.key);
      expect(
          flatten(matches!).map((match) => match.name), contains(entry.value),
          reason: entry.key);
    }
  });
}
