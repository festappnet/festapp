import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/occasion_administration_boundary.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/navigation/routed_day_tabs.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';

class Access extends ChangeNotifier implements AdministrationAccess {
  bool signedIn = true;
  bool allowed = true;
  String? identity;
  final List<String> requests = [];
  Future<void> Function(String)? beforeLoad;
  @override
  bool get isSignedIn => signedIn;
  @override
  String? get loadedLink => identity;
  @override
  Listenable get changes => this;
  @override
  bool canAccess({required bool reservations}) => signedIn && allowed;
  @override
  Future<bool> load(String link, {required bool reservations}) async {
    requests.add(link);
    await beforeLoad?.call(link);
    identity = link;
    notifyListeners();
    return allowed;
  }
}

class FixtureRouter extends RootStackRouter {
  final Access access;
  WidgetBuilder? formsListBuilder;
  bool extra = true;
  bool dirty = false;
  bool discard = false;
  int prompts = 0;
  FixtureRouter(this.access);
  @override
  List<AutoRouteGuard> get guards => [RetainedDraftGuard.instance];
  AutoRoute page(String name, String path, WidgetBuilder builder,
          {List<AutoRoute>? children}) =>
      AutoRoute(
          page: PageInfo(name, builder: (data) => Builder(builder: builder)),
          path: path,
          children: children);
  @override
  List<AutoRoute> get routes => [
        page(
            ReservationsRoute.name,
            '/:{occasionLink}/reservations',
            (context) => OccasionAdministrationBoundary(
                access: access,
                reservations: true,
                builder: (context) => const AutoRouter()),
            children: [
              page(
                  ReservationsTabsRoute.name,
                  '',
                  (context) => ListenableBuilder(
                      listenable: access,
                      builder: (context, _) => RoutedTabScaffold(tabs: [
                            const RoutedTabDefinition(
                                slug: 'orders',
                                route: OrdersTabsRoute(),
                                label: 'Orders',
                                icon: Icons.shopping_cart),
                            if (extra)
                              const RoutedTabDefinition(
                                  slug: 'forms',
                                  route: FormsNavigationRoute(),
                                  label: 'Forms',
                                  icon: Icons.article),
                          ])),
                  children: [
                    RedirectRoute(path: '', redirectTo: 'orders'),
                    page(
                        OrdersTabsRoute.name,
                        'orders',
                        (context) => const RoutedTabScaffold(tabs: [
                              RoutedTabDefinition(
                                  slug: 'current',
                                  route: OrdersCurrentRoute(),
                                  label: 'Current',
                                  icon: Icons.list),
                              RoutedTabDefinition(
                                  slug: 'history',
                                  route: OrdersHistoryRoute(),
                                  label: 'History',
                                  icon: Icons.history),
                            ]),
                        children: [
                          RedirectRoute(path: '', redirectTo: 'current'),
                          page(OrdersCurrentRoute.name, 'current',
                              (context) => const Text('CURRENT CONTENT')),
                          page(OrdersHistoryRoute.name, 'history',
                              (context) => const Text('HISTORY CONTENT'))
                        ]),
                    page(FormsNavigationRoute.name, 'forms',
                        (context) => const AutoRouter(),
                        children: [
                          page(
                              FormsListRoute.name,
                              '',
                              (context) =>
                                  formsListBuilder?.call(context) ??
                                  const Text('FORMS LIST')),
                          page(
                              FormDetailRoute.name,
                              ':formLink',
                              (context) => const RoutedTabScaffold(tabs: [
                                    RoutedTabDefinition(
                                        slug: 'editor',
                                        route: FormEditorRoute(),
                                        label: 'Editor',
                                        icon: Icons.edit),
                                    RoutedTabDefinition(
                                        slug: 'responses',
                                        route: FormResponsesRoute(),
                                        label: 'Responses',
                                        icon: Icons.list),
                                  ]),
                              children: [
                                RedirectRoute(path: '', redirectTo: 'editor'),
                                page(
                                    FormEditorRoute.name,
                                    'editor',
                                    (context) => NavigationDraftBoundary(
                                        isDirty: () => dirty,
                                        confirm: () async {
                                          prompts++;
                                          return discard;
                                        },
                                        child: const Material(
                                            child: TextField(
                                                key: Key('draft-field'))))),
                                page(
                                    FormResponsesRoute.name,
                                    'responses',
                                    (context) =>
                                        const Text('RESPONSES CONTENT'))
                              ]),
                        ]),
                  ]),
              page(NavigationNotFoundRoute.name, '*',
                  (context) => const NavigationNotFoundPage()),
            ]),
        page(
            LoginRoute.name,
            '/login',
            (context) => Text(
                'LOGIN ${context.routeData.queryParams.getString('redirect')}')),
        page(
            'DayRoute',
            '/calendar',
            (context) => RoutedDayTabs(
                days: [DateTime(2026, 10, 3), DateTime(2026, 10, 10)],
                child: const Scaffold(
                    appBar: _DayBar(),
                    body: TabBarView(
                        children: [Text('FIRST DAY'), Text('SECOND DAY')])))),
      ];
}

class _DayBar extends StatelessWidget implements PreferredSizeWidget {
  const _DayBar();
  @override
  Size get preferredSize => const Size.fromHeight(48);
  @override
  Widget build(BuildContext context) =>
      const TabBar(tabs: [Tab(text: '3 October'), Tab(text: '10 October')]);
}
