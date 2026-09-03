import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/users/views/reset_password_page.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/occasion/admin_page.dart';

void main() {
  test('occasion landing path targets the program route', () {
    expect(AppRouter.getOccasionLandingPath('av2025'), '/av2025/event');
  });

  test('matches an occasion program deep link including its schedule root', () {
    final matches = AppRouter().matcher.match(
          '/2025-copy-98cf835a/event',
          includePrefixMatches: false,
        );

    expect(matches, isNotNull);
    expect(
      _flatten(matches!).map((match) => match.name),
      containsAllInOrder([
        'OccasionHomeRoute',
        'ScheduleNavigationRoute',
        anyOf('ScheduleRoute', 'ScheduleLightRoute', 'ScheduleBasicRoute'),
      ]),
    );
  });

  test('matches an occasion admin deep link as the admin page', () {
    final matches = AppRouter().matcher.match(
          '/hvezdamorska/${AdminPage.ROUTE}',
          includePrefixMatches: false,
        );

    expect(matches, isNotNull);
    expect(matches, hasLength(1));
    expect(matches!.single.name, 'AdminRoute');
  });

  test('matches the password-reset route with its token query', () {
    final matches = AppRouter().matcher.match(
          '/resetPassword?token=00000000-0000-0000-0000-000000000000',
        );

    expect(matches, isNotNull);
    expect(matches, hasLength(1));
    expect(matches!.single.name, 'ResetPasswordRoute');
    expect(matches.single.queryParams.getString('token'),
        '00000000-0000-0000-0000-000000000000');
  });

  testWidgets('renders the password-reset page from an initial deep link',
      (tester) async {
    const resetPath =
        '/resetPassword?token=00000000-0000-0000-0000-000000000000';
    final router = AppRouter();

    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router.config(
        deepLinkBuilder: (_) => const DeepLink.path(
          resetPath,
          includePrefixMatches: false,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ResetPasswordPage), findsOneWidget);
    expect(
      tester.widget<ResetPasswordPage>(find.byType(ResetPasswordPage)).token,
      '00000000-0000-0000-0000-000000000000',
    );
  });
}

Iterable<RouteMatch> _flatten(List<RouteMatch> matches) sync* {
  for (final match in matches) {
    yield match;
    yield* _flatten(match.children ?? const []);
  }
}
