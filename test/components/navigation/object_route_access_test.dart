import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/forms/views/form_tab.dart';
import 'package:fstapp/components/forms/models/form_model.dart';
import 'package:fstapp/components/inventory/views/inventory_pool_detail_view.dart';
import 'package:fstapp/components/inventory/models/inventory_pools_list_bundle.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_navigation_page.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/data_services/rights_service.dart';

class ObjectFixture extends RootStackRouter {
  Future<List<FormModel>> Function(String) forms = (_) async => [
        FormModel(id: 1, link: 'first', title: 'First', occasionId: 1),
        FormModel(id: 2, link: 'second', title: 'Second', occasionId: 1)
      ];
  Future<InventoryPoolsListBundle> Function(String) pools = (_) async =>
      InventoryPoolsListBundle(
          occasion: OccasionModel(
              id: 1,
              link: 'occasion-a',
              isOpen: true,
              isHidden: false,
              isPromoted: false),
          pools: [
            InventoryPoolModel(id: 42, title: 'Room pool', occasionId: 1)
          ],
          inventoryContexts: [],
          spots: []);
  Future<List<BankAccountModel>> Function(int) accounts = (_) async =>
      [BankAccountModel(id: 9, title: 'Unit account', isAdmin: true)];
  AutoRoute page(String name, String path, Widget Function(RouteData) builder,
          {List<AutoRoute>? children}) =>
      AutoRoute(
          page: PageInfo(name, builder: builder),
          path: path,
          children: children);
  AutoRoute text(String name, String path, String value) =>
      page(name, path, (_) => Text(value));
  @override
  List<AutoRoute> get routes => [
        page(ReservationsRoute.name, '/:{occasionLink}/reservations',
            (_) => const AutoRouter(),
            children: [
              page(
                  FormsNavigationRoute.name, 'forms', (_) => const AutoRouter(),
                  children: [
                    text(FormsListRoute.name, '', 'FORM LIST'),
                    page(
                        FormDetailRoute.name,
                        ':formLink',
                        (data) => FormDetailPage(
                            formLink: data.params.getString('formLink'),
                            loadForms: forms),
                        children: [
                          page(FormTabsRoute.name, '', (_) => const FormTab(),
                              children: [
                                text(FormEditorRoute.name, 'editor',
                                    'FORM EDITOR'),
                                text(FormSettingsRoute.name, 'settings',
                                    'FORM SETTINGS'),
                                text(FormDesignRoute.name, 'design',
                                    'FORM DESIGN'),
                                text(FormResponsesRoute.name, 'responses',
                                    'FORM RESPONSES')
                              ])
                        ])
                  ]),
              page(InventoryPoolsNavigationRoute.name, 'inventory-pools',
                  (_) => const AutoRouter(),
                  children: [
                    text(InventoryPoolsListRoute.name, '', 'POOL LIST'),
                    page(
                        InventoryPoolDetailRoute.name,
                        ':poolId',
                        (data) => InventoryPoolDetailPage(
                            poolId: data.params.getString('poolId'),
                            loadPools: pools),
                        children: [
                          page(InventoryPoolTabsRoute.name, '',
                              (_) => const InventoryPoolDetailView(),
                              children: [
                                text(InventoryPoolOccupancyRoute.name,
                                    'occupancy', 'POOL OCCUPANCY'),
                                text(InventoryPoolRoomsRoute.name, 'rooms',
                                    'POOL ROOMS'),
                                text(InventoryPoolSettingsRoute.name,
                                    'settings', 'POOL SETTINGS')
                              ])
                        ])
                  ]),
            ]),
        page(
            UnitAdminRoute.name,
            '/unit/:id/edit',
            (_) => UnitAdministrationScope(
                unit: UnitModel(id: 5),
                occasions: const [],
                onUpdated: () {},
                child: const AutoRouter()),
            children: [
              page(UnitBankAccountsNavigationRoute.name, 'bank-accounts',
                  (_) => const AutoRouter(),
                  children: [
                    text(UnitBankAccountsListRoute.name, '', 'ACCOUNT LIST'),
                    page(
                        BankAccountDetailRoute.name,
                        ':accountId',
                        (data) => BankAccountDetailPage(
                            accountId: data.params.getString('accountId'),
                            loadAccounts: accounts),
                        children: [
                          page(BankAccountTabsRoute.name, '',
                              (_) => const BankAccountTabsPage(),
                              children: [
                                text(BankAccountGeneralRoute.name, 'general',
                                    'ACCOUNT GENERAL'),
                                text(BankAccountConnectionRoute.name,
                                    'connection', 'ACCOUNT CONNECTION'),
                                text(BankAccountUsersRoute.name, 'users',
                                    'ACCOUNT USERS')
                              ])
                        ])
                  ])
            ]),
      ];
}

Future<void> mount(
    WidgetTester tester, ObjectFixture router, String path) async {
  await tester.pumpWidget(MaterialApp.router(
      routerConfig: router.config(
          deepLinkBuilder: (link) =>
              link.initial ? DeepLink.path(path) : link)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    RightsService.currentLink = 'occasion-a';
    RightsService.occasionLinkModelNotifier.value =
        OccasionLinkModel(code: 200, unit: UnitModel(id: 5));
  });
  tearDown(() {
    RightsService.currentLink = null;
    RightsService.occasionLinkModelNotifier.value = null;
  });
  testWidgets(
      'direct responses URL validates the second form and Back reconstructs the list',
      (tester) async {
    final router = ObjectFixture();
    await mount(
        tester, router, '/occasion-a/reservations/forms/second/responses');
    expect(find.text('FORM RESPONSES'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/forms?list=true');
    expect(find.text('FORM LIST'), findsOneWidget);
  });
  for (final id in ['deleted', 'foreign']) {
    testWidgets('a $id form never creates its child', (tester) async {
      final router = ObjectFixture();
      await mount(
          tester, router, '/occasion-a/reservations/forms/$id/responses');
      expect(find.text('Not found or access denied'), findsOneWidget);
      expect(find.text('FORM RESPONSES'), findsNothing);
    });
  }
  testWidgets('pool settings validate pool membership before child creation',
      (tester) async {
    final router = ObjectFixture();
    await mount(
        tester, router, '/occasion-a/reservations/inventory-pools/42/settings');
    expect(find.text('POOL SETTINGS'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/inventory-pools');
    expect(find.text('POOL LIST'), findsOneWidget);
  });
  for (final id in ['999', 'invalid']) {
    testWidgets('missing or malformed pool $id is controlled', (tester) async {
      final router = ObjectFixture();
      await mount(tester, router,
          '/occasion-a/reservations/inventory-pools/$id/settings');
      expect(find.text('Not found or access denied'), findsOneWidget);
      expect(find.text('POOL SETTINGS'), findsNothing);
    });
  }
  testWidgets('existing account users URL shares the real bank editor',
      (tester) async {
    final router = ObjectFixture();
    await mount(tester, router, '/unit/5/edit/bank-accounts/9/users');
    expect(find.text('ACCOUNT USERS'), findsOneWidget);
    expect(find.text('Unit account'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/unit/5/edit/bank-accounts');
    expect(find.text('ACCOUNT LIST'), findsOneWidget);
  });
  testWidgets(
      'bank membership uses the loaded unit scope during rights refresh',
      (tester) async {
    final router = ObjectFixture();
    router.accounts = (unitId) async {
      expect(unitId, 5);
      RightsService.occasionLinkModelNotifier.value =
          OccasionLinkModel(code: 200, unit: UnitModel(id: 6));
      return [BankAccountModel(id: 9, title: 'Unit account', isAdmin: true)];
    };
    await mount(tester, router, '/unit/5/edit/bank-accounts/9/users');
    expect(find.text('ACCOUNT USERS'), findsOneWidget);
    expect(find.text('Not found or access denied'), findsNothing);
  });
  testWidgets('a foreign account cannot mount bank tabs', (tester) async {
    final router = ObjectFixture();
    await mount(tester, router, '/unit/5/edit/bank-accounts/88/users');
    expect(find.text('Not found or access denied'), findsOneWidget);
    expect(find.text('ACCOUNT USERS'), findsNothing);
  });
  testWidgets('changing form identity ignores a stale membership load',
      (tester) async {
    final old = Completer<List<FormModel>>();
    var calls = 0;
    final router = ObjectFixture()
      ..forms = (_) => ++calls == 1
          ? old.future
          : Future.value([FormModel(id: 2, link: 'second', title: 'Second')]);
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router.config(
            deepLinkBuilder: (link) => const DeepLink.path(
                '/occasion-a/reservations/forms/first/responses'))));
    for (var i = 0; i < 10 && calls == 0; i++) {
      await tester.pump();
    }
    expect(calls, 1);
    await router.navigate(router.buildPageRoute(
        '/occasion-a/reservations/forms/second/responses',
        includePrefixMatches: false)!);
    await tester.pumpAndSettle();
    old.complete([FormModel(id: 1, link: 'first', title: 'First')]);
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(
        router.currentUrl, '/occasion-a/reservations/forms/second/responses');
  });
}
