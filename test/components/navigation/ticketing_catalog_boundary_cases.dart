import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/widgets/dependency_material_bridge.dart';

class _HistoryRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    for (final route in AppRouter().routes)
      if (route.path == '/' || route.path == '/unit/:id') route,
    CustomRoute(
      path: '/login',
      transitionsBuilder: TransitionsBuilders.noTransition,
      page: PageInfo(
        LoginRoute.name,
        builder: (_) => const Scaffold(body: Text('SAFE_LOGIN')),
      ),
    ),
    CustomRoute(
      path: '/unit/:id/edit',
      transitionsBuilder: TransitionsBuilders.noTransition,
      page: PageInfo(
        UnitAdminRoute.name,
        builder: (_) => const Scaffold(body: Text('SAFE_ADMIN')),
      ),
    ),
  ];
}

void main() {
  test('profile route registration excludes the public catalogue in ticketing mode', () {
    final router = AppRouter();
    for (final path in ['/', '/unit/7']) {
      final matches = router.matcher.match(path, includePrefixMatches: false)!;
      if (AppConfig.isAppSupported) {
        expect(
          matches.single.name,
          path == '/' ? OrganizationRoute.name : UnitRoute.name,
        );
      } else {
        expect(
          matches.map((route) => route.name),
          isNot(contains(OrganizationRoute.name)),
          reason: path,
        );
        expect(
          matches.map((route) => route.name),
          isNot(contains(UnitRoute.name)),
          reason: path,
        );
        expect(
          matches.single.name,
          path == '/' ? LoginRoute.name : UnitAdminRoute.name,
          reason: path,
        );
      }
    }
  });

  testWidgets(
    'Back from administration cannot reveal the unsupported root catalogue',
    (tester) async {
      final router = _HistoryRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          builder: DependencyMaterialBridge.builder,
          routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink.path('/'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SAFE_LOGIN'), findsOneWidget);
      final opened = router.pushPath('/unit/7/edit');
      await tester.pumpAndSettle();
      expect(find.text('SAFE_ADMIN'), findsOneWidget);
      await router.maybePop();
      await opened;
      await tester.pumpAndSettle();
      expect(find.text('SAFE_LOGIN'), findsOneWidget);
      expect(
        router.stack.map((page) => page.name),
        isNot(contains(OrganizationRoute.name)),
      );
    },
    skip: AppConfig.isAppSupported,
  );

  testWidgets(
    'legacy unit navigation opens administration and clears the catalogue history',
    (tester) async {
      final router = _HistoryRouter();
      await tester.pumpWidget(
        MaterialApp.router(
          builder: DependencyMaterialBridge.builder,
          routerConfig: router.config(
            deepLinkBuilder: (_) => const DeepLink.path('/'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await RouterService.goToUnit(tester.element(find.text('SAFE_LOGIN')), 7);
      await tester.pumpAndSettle();
      expect(find.text('SAFE_ADMIN'), findsOneWidget);
      expect(router.stack.map((page) => page.name), [UnitAdminRoute.name]);
    },
    skip: AppConfig.isAppSupported,
  );
}
