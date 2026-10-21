import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/inventory/views/inventory_pools_tab.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/components/inventory/models/inventory_pools_list_bundle.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import '../../support/fixtures/widget_environment_fixture.dart';
import 'object_route_access_cases.dart' show ObjectFixture, mount;

void main() {
  WidgetEnvironmentFixture.register();
  late WidgetEnvironmentFixture environment;
  setUpAll(() {
    environment = WidgetEnvironmentFixture(
        locale: const Locale('cs'),
        translations:
            jsonDecode(File('assets/translations/cs.json').readAsStringSync()));
  });
  setUp(() {
    final previousLink = RightsService.currentLink;
    final previousRights = RightsService.occasionLinkModelNotifier.value;
    addTearDown(() {
      RightsService.currentLink = previousLink;
      RightsService.occasionLinkModelNotifier.value = previousRights;
    });
    RightsService.currentLink = 'occasion-a';
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(code: 200, unit: UnitModel(id: 5));
  });
  testWidgetsWithEnvironment(() => environment,
      'single pool opens directly, preserves queries and can return to the list',
      (tester) async {
    final router = ObjectFixture();
    router.poolListBuilder = () => InventoryPoolsTab(loadPools: router.pools);
    await mount(tester, router,
        '/occasion-a/reservations/inventory-pools?day=2026-10-03',
        environment: environment);
    expect(find.text('Room pool'), findsOneWidget);
    expect(find.text('POOL OCCUPANCY'), findsOneWidget);
    expect(Uri.parse(router.currentUrl).queryParameters['day'], '2026-10-03');
    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    await tester.pumpAndSettle();
    expect(find.text('POOL OCCUPANCY'), findsNothing);
    expect(Uri.parse(router.currentUrl).queryParameters['list'], 'true');
    expect(Uri.parse(router.currentUrl).queryParameters['day'], '2026-10-03');
  });

  testWidgetsWithEnvironment(() => environment,
      'pool title resets the selected subtab, as the form title does',
      (tester) async {
    final router = ObjectFixture();
    await mount(tester, router,
        '/occasion-a/reservations/inventory-pools/42/settings?day=2026-10-03',
        environment: environment);
    await tester.tap(find.text('Room pool'));
    await tester.pumpAndSettle();
    expect(find.text('POOL OCCUPANCY'), findsOneWidget);
    expect(find.text('POOL SETTINGS'), findsNothing);
    expect(Uri.parse(router.currentUrl).queryParameters['day'], '2026-10-03');
  });

  testWidgetsWithEnvironment(() => environment,
      'pool selector changes identity and opens its default subtab',
      (tester) async {
    final router = ObjectFixture();
    final original = router.pools;
    router.pools = (link) async {
      final bundle = await original(link);
      return InventoryPoolsListBundle(occasion: bundle.occasion, pools: [
        ...bundle.pools,
        InventoryPoolModel(id: 43, title: 'Food pool', occasionId: 1)
      ], inventoryContexts: [], spots: []);
    };
    await mount(
        tester, router, '/occasion-a/reservations/inventory-pools/42/settings',
        environment: environment);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    await tester.tap(find.text('Room pool'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food pool'));
    await tester.pumpAndSettle();
    expect(router.currentUrl,
        '/occasion-a/reservations/inventory-pools/43/occupancy');
    expect(find.text('Food pool'), findsOneWidget);
    expect(find.text('POOL OCCUPANCY'), findsOneWidget);
  });
  testWidgetsWithEnvironment(() => environment,
      'pool selector respects a dirty editor before changing identity',
      (tester) async {
    final router = ObjectFixture();
    var allow = false;
    var prompts = 0;
    router.poolSettingsBuilder = () => NavigationDraftBoundary(
        isDirty: () => true,
        confirm: () async {
          prompts++;
          return allow;
        },
        child: const Text('POOL SETTINGS'));
    final original = router.pools;
    router.pools = (link) async {
      final bundle = await original(link);
      return InventoryPoolsListBundle(occasion: bundle.occasion, pools: [
        ...bundle.pools,
        InventoryPoolModel(id: 43, title: 'Food pool', occasionId: 1)
      ], inventoryContexts: [], spots: []);
    };
    await mount(
        tester, router, '/occasion-a/reservations/inventory-pools/42/settings',
        environment: environment);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    await tester.tap(find.text('Room pool'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food pool'));
    await tester.pumpAndSettle();
    expect(prompts, 1);
    expect(router.currentUrl,
        '/occasion-a/reservations/inventory-pools/42/settings');
    expect(find.text('POOL SETTINGS'), findsOneWidget);
    allow = true;
    await tester.tap(find.text('Room pool'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food pool'));
    await tester.pumpAndSettle();
    expect(prompts, 2);
    expect(router.currentUrl,
        '/occasion-a/reservations/inventory-pools/43/occupancy');
    expect(find.text('Food pool'), findsOneWidget);
    expect(find.text('POOL OCCUPANCY'), findsOneWidget);
  });
}
