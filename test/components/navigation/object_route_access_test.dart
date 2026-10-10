import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/services.dart';
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
import 'package:fstapp/components/bank_accounts/views/bank_accounts_load_scope.dart';
import 'package:fstapp/components/bank_accounts/views/bank_account_settings_screen.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/views/unit_admin_page.dart';
import 'package:fstapp/data_services/rights_service.dart';

class ObjectFixture extends RootStackRouter {
  bool realBankGeneral = false;
  WidgetBuilder? bankListBuilder;
  final unitVisible = ValueNotifier(true);
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
          initial: path.isEmpty,
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
                child: ValueListenableBuilder<bool>(
                    valueListenable: unitVisible,
                    builder: (context, visible, child) => Scaffold(
                        appBar: AppBar(title: const Text('UNIT HEADER')),
                        body: TickerMode(
                            enabled: visible, child: const AutoRouter())))),
            children: [
              page(
                  UnitBankAccountsNavigationRoute.name,
                  'bank-accounts',
                  (_) => BankAccountsNavigationView(
                      loadAccounts: accounts,
                      listBuilder: (context) =>
                          bankListBuilder?.call(context) ??
                          const Text('ACCOUNT LIST')),
                  children: [
                    page(UnitBankAccountsListRoute.name, '',
                        (_) => const UnitBankAccountsListPage()),
                    page(
                        BankAccountDetailRoute.name,
                        ':accountId',
                        (data) => BankAccountDetailPage(
                            accountId: data.params.getString('accountId')),
                        children: [
                          page(BankAccountTabsRoute.name, '',
                              (_) => const BankAccountTabsPage(),
                              children: [
                                RedirectRoute(path: '', redirectTo: 'general'),
                                page(
                                    BankAccountGeneralRoute.name,
                                    'general',
                                    (_) => realBankGeneral
                                        ? const BankAccountGeneralPage()
                                        : const Text('ACCOUNT GENERAL')),
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
  testWidgets(
      'bank dialog retains its overlay while sharing the initial list load',
      (tester) async {
    final pending = Completer<List<BankAccountModel>>();
    var requests = 0;
    final router = ObjectFixture()
      ..accounts = (_) {
        requests++;
        return pending.future;
      };
    router.bankListBuilder = (context) => FutureBuilder<List<BankAccountModel>>(
        future: BankAccountsLoadScope.maybeOf(context)!.load(false),
        builder: (_, snapshot) =>
            Text(snapshot.hasData ? 'ACCOUNT LIST' : 'LOADING LIST'));
    await tester.pumpWidget(MaterialApp.router(
        routerConfig: router.config(
            deepLinkBuilder: (_) =>
                const DeepLink.path('/unit/5/edit/bank-accounts/9/general'))));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(Dialog), findsOneWidget);
    final overlayState = tester.state(find.byType(RoutedBankAccountDialog));
    expect(requests, 1);
    pending.complete(
        [BankAccountModel(id: 9, title: 'Unit account', isAdmin: true)]);
    await tester.pumpAndSettle();
    expect(
        tester.state(find.byType(RoutedBankAccountDialog)), same(overlayState));
    expect(requests, 1);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isFalse);
    expect(
        tabBar.tabs
            .every((tab) => tab is Tab && tab.icon == null && tab.text != null),
        isTrue);
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/unit/5/edit/bank-accounts');
    expect(requests, 2, reason: 'Closing refreshes the list exactly once');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('bank list edit click opens and reopens the routed dialog',
      (tester) async {
    final router = ObjectFixture();
    router.bankListBuilder = (context) => Center(
        child: IconButton(
            key: const Key('edit-account'),
            icon: const Icon(Icons.edit),
            onPressed: () => unawaited(
                context.router.push(BankAccountDetailRoute(accountId: '9')))));
    await mount(tester, router, '/unit/5/edit/bank-accounts');
    await tester.tap(find.byKey(const Key('edit-account')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(router.currentUrl, '/unit/5/edit/bank-accounts/9/general');
    expect(find.text('ACCOUNT GENERAL'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'BankAccount.cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-account')));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

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
    final header = tester.widget<AppBar>(find.byType(AppBar).last);
    expect(header.toolbarHeight, 44);
    expect(header.leading, isNull);
    expect(find.byIcon(Icons.unfold_more_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/occasion-a/reservations/forms?list=true');
    expect(find.text('FORM LIST'), findsOneWidget);
  });
  for (final single in [true, false]) {
    testWidgets('form breadcrumb returns to editor (single: $single)',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = ObjectFixture();
      if (single)
        router.forms =
            (_) async => [FormModel(id: 2, link: 'second', title: 'Second')];
      await mount(
          tester, router, '/occasion-a/reservations/forms/second/design');
      expect(find.text('FORM DESIGN'), findsOneWidget);
      await tester.tap(find.text('Second'));
      if (!single) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second').last);
      }
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/occasion-a/reservations/forms/second/editor');
      expect(find.text('FORM EDITOR'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
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
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('ACCOUNT LIST'), findsOneWidget);
    expect(
        tester.getRect(find.byWidgetPredicate((widget) =>
            widget is ModalBarrier && widget.color == Colors.black54)),
        const Rect.fromLTWH(0, 0, 800, 600));
    expect(
        tester
            .getSize(find
                .descendant(
                    of: find.byType(Dialog), matching: find.byType(Material))
                .first)
            .width,
        lessThanOrEqualTo(600));
    await tester.tap(find.widgetWithText(TextButton, 'BankAccount.cancel'));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/unit/5/edit/bank-accounts');
    expect(find.text('ACCOUNT LIST'), findsOneWidget);
  });
  for (final closeWith in ['barrier', 'escape']) {
    testWidgets('routed bank dialog closes through $closeWith', (tester) async {
      final router = ObjectFixture();
      await mount(tester, router, '/unit/5/edit/bank-accounts/9/connection');
      expect(find.byType(Dialog), findsOneWidget);
      if (closeWith == 'barrier') {
        await tester.tapAt(const Offset(10, 10));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pumpAndSettle();
      expect(router.currentUrl, '/unit/5/edit/bank-accounts');
    });
  }
  testWidgets('a retained inactive section hides its root overlay',
      (tester) async {
    final router = ObjectFixture();
    await mount(tester, router, '/unit/5/edit/bank-accounts/9/users');
    expect(find.byType(Dialog), findsOneWidget);
    router.unitVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    router.unitVisible.value = true;
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(router.currentUrl, '/unit/5/edit/bank-accounts/9/users');
  });
  testWidgets('dirty bank dialog can cancel barrier dismissal', (tester) async {
    Localization.load(const Locale('cs'),
        translations: Translations(jsonDecode(
            File('assets/translations/cs.json').readAsStringSync())));
    final router = ObjectFixture()..realBankGeneral = true;
    await mount(tester, router, '/unit/5/edit/bank-accounts/9/general');
    final title = find.widgetWithText(TextFormField, 'Unit account');
    await tester.enterText(title, 'Unsaved title');
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Storno')));
    await tester.pumpAndSettle();
    expect(router.currentUrl, '/unit/5/edit/bank-accounts/9/general');
    expect(find.text('Unsaved title'), findsOneWidget);
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
