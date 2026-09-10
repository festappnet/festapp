import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:badges/badges.dart' as badges;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/async_reload_coordinator.dart';
import 'package:fstapp/components/occasion/occasion_home_strings.dart';
import 'package:fstapp/components/occasion/occasion_link_model.dart';
import 'package:fstapp/components/occasion/news_badge_controller.dart';
import 'package:fstapp/components/offline/offline_banner.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/update_service.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_protocol.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/news/db_news.dart';
import 'package:fstapp/components/users/views/login_page.dart';
import 'package:fstapp/services/notification_helper.dart';
import 'package:fstapp/services/web_styles_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/map/map_page.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:fstapp/components/schedule/event_page.dart';
import 'package:fstapp/components/schedule/timetable_page.dart';
import 'package:fstapp/components/news/news_page.dart';
import 'package:fstapp/components/information/info_page.dart';
import 'package:fstapp/components/unit/views/unit_page.dart';
import 'package:fstapp/components/users/views/user_page.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/schedule_feature.dart';
import 'package:fstapp/components/search/global_search_dialog.dart';
import 'package:fstapp/components/search/search_strings.dart';

@RoutePage()
class OccasionHomePage extends StatefulWidget {
  static const homePageTitle = AppConfig.appName;

  const OccasionHomePage({super.key});

  /// Base bottom-nav tabs. When the GlobalSearch feature is enabled the "user"
  /// tab is dropped (profile moves to the app bar) and a "search" tab is
  /// appended — see [_OccasionHomePageState.visibleTabKeys].
  static final List<String> baseTabKeys = [
    if (AppConfig.isAllUnit) OccasionTab.unit,
    if (!AppConfig.isAllUnit) OccasionTab.home,
    OccasionTab.map,
    OccasionTab.news,
    OccasionTab.more,
  ];

  @override
  State<OccasionHomePage> createState() => _OccasionHomePageState();
}

class _OccasionHomePageState extends State<OccasionHomePage>
    with WidgetsBindingObserver {
  int _messageCount = 0;
  final AsyncReloadCoordinator _reloadCoordinator = AsyncReloadCoordinator();
  final AsyncReloadCoordinator _newsReadCoordinator = AsyncReloadCoordinator();
  final PublicMapSession _mapSession = PublicMapSession();
  late final _AutoRouteMapNavigationAdapter _mapNavigation =
      _AutoRouteMapNavigationAdapter();
  TabsRouter? _tabsRouter;
  late final Map<String, OccasionTab> _availableTabs;

  /// Effective bottom-nav keys: when GlobalSearch is on, the profile ("user")
  /// tab is replaced by a "search" tab (profile moves to the app bar), matching
  /// production. Otherwise the default profile tab is shown.
  List<String> get visibleTabKeys => [
        ...OccasionHomePage.baseTabKeys,
        if (FeatureService.isFeatureEnabled(FeatureConstants.globalSearch))
          OccasionTab.search
        else
          OccasionTab.user,
      ];

  @override
  void initState() {
    super.initState();
    _availableTabs = OccasionTab.getAvailableTabs(_acknowledgeActiveNews);
    WidgetsBinding.instance.addObserver(this);
    _mapSession.bindNavigation(_mapNavigation);
    loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: ThemeConfig.logoBackgroundColor(context),
      systemNavigationBarColor: ThemeConfig.appBarColor(),
    ));
    WebStylesHelper.setBodyBackgroundColor(ThemeConfig.appBarColor());
    WebStylesHelper.setMetaThemeColor(ThemeConfig.seed1);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ClientSyncRuntime.setForeground(true);
      loadData();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      ClientSyncRuntime.setForeground(false);
    }
  }

  @override
  void dispose() {
    _tabsRouter?.removeListener(_onTabsChanged);
    _mapSession.unbindNavigation(_mapNavigation);
    _mapSession.dispose();
    _mapNavigation.dispose();
    _reloadCoordinator.dispose();
    _newsReadCoordinator.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _bindTabsRouter(BuildContext context, TabsRouter tabsRouter) {
    _mapNavigation.context = context;
    _mapNavigation.tabsRouter = tabsRouter;
    _mapNavigation.mapIndex = visibleTabKeys.indexOf(OccasionTab.map);
    if (identical(_tabsRouter, tabsRouter)) return;
    _tabsRouter?.removeListener(_onTabsChanged);
    _tabsRouter = tabsRouter;
    tabsRouter.addListener(_onTabsChanged);
    scheduleInitialMapTabVisibilitySync(() {
      if (mounted && identical(_tabsRouter, tabsRouter)) {
        _onTabsChanged();
      }
    });
  }

  void _onTabsChanged() {
    final tabsRouter = _tabsRouter;
    if (tabsRouter == null) return;
    final activeKey = tabsRouter.activeIndex >= 0 &&
            tabsRouter.activeIndex < visibleTabKeys.length
        ? visibleTabKeys[tabsRouter.activeIndex]
        : null;
    final mapActive = activeKey == OccasionTab.map;
    _mapNavigation.setVisible(mapActive);
    _mapSession.setVisible(mapActive);
    if (activeKey == OccasionTab.news) _acknowledgeActiveNews();
  }

  void _acknowledgeActiveNews() => _acknowledgeNews(requireActiveTab: true);

  void _acknowledgeSelectedNews() => _acknowledgeNews(requireActiveTab: false);

  void _acknowledgeNews({required bool requireActiveTab}) {
    final tabsRouter = _tabsRouter;
    if (!mounted ||
        tabsRouter == null ||
        (requireActiveTab &&
            (tabsRouter.activeIndex < 0 ||
                tabsRouter.activeIndex >= visibleTabKeys.length ||
                visibleTabKeys[tabsRouter.activeIndex] != OccasionTab.news)) ||
        !AuthService.isLoggedIn()) {
      return;
    }

    setState(() => _messageCount = 0);
    unawaited(_newsReadCoordinator.run(() async {
      final currentRouter = _tabsRouter;
      if (!mounted ||
          currentRouter == null ||
          (requireActiveTab &&
              (currentRouter.activeIndex < 0 ||
                  currentRouter.activeIndex >= visibleTabKeys.length ||
                  visibleTabKeys[currentRouter.activeIndex] !=
                      OccasionTab.news)) ||
          !AuthService.isLoggedIn()) {
        return;
      }
      await DbNews.setLatestMessageAsRead();
      if (mounted) setState(() => _messageCount = 0);
    }));
  }

  Future<void> loadData() => _reloadCoordinator.run(() async {
        await UpdateService.versionCheck(context);
        if (AuthService.isLoggedIn()) {
          DbNews.countNewMessages().then((count) {
            if (mounted) {
              setState(() => _messageCount = count);
            }
          });
        }
        if (!mounted) return;
        await NotificationHelper.checkForNotificationPermission(context);
      });

  String messageCountString() =>
      _messageCount < 100 ? _messageCount.toString() : "99+";

  @override
  Widget build(BuildContext context) {
    return PublicMapSessionScope(
      session: _mapSession,
      child: AutoTabsRouter(
        routes:
            visibleTabKeys.map((key) => _availableTabs[key]!.route).toList(),
        builder: (tabsContext, child) {
          final tabsRouter = AutoTabsRouter.of(tabsContext);
          _bindTabsRouter(tabsContext, tabsRouter);
          return Scaffold(
            bottomNavigationBar: ValueListenableBuilder<bool>(
              valueListenable: MapPage.isEditingNotifier,
              builder: (context, isEditingMap, _) {
                // Hide the bottom navigation while drawing a path on the map.
                if (isEditingMap) return const SizedBox.shrink();
                return ValueListenableBuilder<OccasionLinkModel?>(
                  valueListenable: RightsService.occasionLinkModelNotifier,
                  builder: (listenableContext, occasionLinkModel, __) {
                    final suppressSelection =
                        visibleTabKeys[tabsRouter.activeIndex] ==
                            OccasionTab.search;
                    final unselectedColor =
                        ThemeConfig.bottomNavUnselectedItemColor(
                            listenableContext);
                    return BottomNavigationBar(
                      backgroundColor: ThemeConfig.bottomNavBackgroundColor(
                          listenableContext),
                      selectedItemColor: suppressSelection
                          ? unselectedColor
                          : ThemeConfig.bottomNavSelectedItemColor(
                              listenableContext),
                      unselectedItemColor: unselectedColor,
                      selectedFontSize: suppressSelection ? 12 : 14,
                      currentIndex: tabsRouter.activeIndex,
                      type: BottomNavigationBarType.fixed,
                      onTap: (int index) async {
                        final isReselected = isBottomNavigationReselection(
                          activeIndex: tabsRouter.activeIndex,
                          selectedIndex: index,
                        );
                        final key = visibleTabKeys[index];
                        final tab = _availableTabs[key]!;
                        unawaited(ClientSyncRuntime.refresh(
                            SyncReason.navigation,
                            privateConsumer: tab.requiresLogin));

                        // Search is a modal overlay, not a real tab — show it and
                        // keep the current tab active (matches production).
                        if (key == OccasionTab.search) {
                          GlobalSearchDialog.show(listenableContext);
                          return;
                        }

                        if (tab.requiresLogin && !AuthService.isLoggedIn()) {
                          await RouterService.navigate(
                              listenableContext, LoginPage.ROUTE);
                          await loadData();
                        } else {
                          handleNewsBadgeTabTap(
                            isNewsTab: key == OccasionTab.news,
                            isLoggedIn: AuthService.isLoggedIn(),
                            loadUnreadCount: DbNews.countNewMessages,
                            setUnreadCount: (count) {
                              if (mounted) {
                                setState(() => _messageCount = count);
                              }
                            },
                            acknowledgeUnread: _acknowledgeSelectedNews,
                          );
                          // Switching tabs restores the retained stack exactly
                          // as it was. Only tapping the already active tab is a
                          // request to return that section to its root. Resetting
                          // an inactive Map tab discards its native surface and
                          // forces MapLibre to reload the style and tiles.
                          if (isReselected) {
                            if (key == OccasionTab.map) {
                              await _mapSession.resetToOverview();
                            }
                            await _resetTabToCanonicalRoot(
                              tabsRouter: tabsRouter,
                              index: index,
                              tabKey: key,
                            );
                          }
                          tabsRouter.setActiveIndex(index);
                        }
                      },
                      items: visibleTabKeys.map((key) {
                        final tab = _availableTabs[key]!;
                        return BottomNavigationBarItem(
                          icon: tab.buildIcon(listenableContext, _messageCount,
                              messageCountString),
                          activeIcon: suppressSelection
                              ? tab.buildIcon(listenableContext, _messageCount,
                                  messageCountString)
                              : tab.buildActiveIcon(listenableContext,
                                  _messageCount, messageCountString),
                          label: key == OccasionTab.user
                              ? (occasionLinkModel?.userInfo?.name ??
                                  UserStrings.signIn)
                              : tab.label,
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
            body: Column(
              children: [
                // Projection refreshes are consumed by each retained tab's
                // data listeners. Never key the whole tab host: that remounts
                // the native map surface and discards its warm camera.
                const OfflineBanner(),
                // AutoTabsRouter retains each tab's page state. Rendering a
                // second MapPage beside its PublicMapRoute creates two native
                // platform views and duplicates lifecycle side effects.
                Expanded(child: child),
              ],
            ),
          );
        },
      ),
    );
  }
}

@visibleForTesting
bool isBottomNavigationReselection({
  required int activeIndex,
  required int selectedIndex,
}) =>
    activeIndex == selectedIndex;

@visibleForTesting
void scheduleInitialMapTabVisibilitySync(VoidCallback synchronize) {
  WidgetsBinding.instance.addPostFrameCallback((_) => synchronize());
}

Future<void> _resetTabToCanonicalRoot({
  required TabsRouter tabsRouter,
  required int index,
  required String tabKey,
}) async {
  final stackRouter = tabsRouter.stackRouterOfIndex(index);
  if (stackRouter == null) return;

  // An absolute /event/:id deep link can make EventRoute the first navigator
  // entry, so popUntilRoot would keep the detail open. Replace only the
  // program tab's nested stack with its configured empty-path route. The
  // AutoTabsRouter shell and every other retained tab (especially MapLibre)
  // stay mounted.
  if (tabKey == OccasionTab.home) {
    final root = stackRouter.routeCollection.routes.firstWhere(
      (route) => route.path.isEmpty,
      orElse: () => throw StateError('Program tab has no canonical root.'),
    );
    await stackRouter.replaceAll([PageRouteInfo<void>(root.name)]);
    return;
  }

  // Preserve the warm native map surface for ordinary overview reselection.
  // A deep-linked place/category can itself be the nested router's first
  // entry, so popUntilRoot would leave a non-canonical URL and could reapply
  // its intent after a later remount. Replace only that non-overview route.
  if (tabKey == OccasionTab.map) {
    final current = stackRouter.current;
    final isCanonicalOverview = current.name == PublicMapRoute.name &&
        current.params.getString(
              'destination',
              PublicMapPage.overviewDestination,
            ) ==
            PublicMapPage.overviewDestination &&
        current.queryParams.optString('placeType') == null;
    if (!isCanonicalOverview) {
      await stackRouter.replaceAll([
        PublicMapRoute(destination: PublicMapPage.overviewDestination),
      ]);
    }
    return;
  }

  stackRouter.popUntilRoot();
}

class OccasionTab {
  final String key;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final PageRouteInfo<dynamic> route;
  final bool requiresLogin;

  /// Occasion-relative path of this section's homepage (e.g. "event", "map").
  /// Used by the bottom nav to always return to the section root on tap, even
  /// from a deep-linked nested detail. Null for tabs without a page (search).
  final String? path;

  OccasionTab({
    required this.key,
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.route,
    this.requiresLogin = false,
    this.path,
  });

  static const String unit = "unit";
  static const String home = "home";
  static const String news = "news";
  static const String map = "map";
  static const String more = "more";
  static const String user = "user";
  static const String timetable = "timetable";
  static const String search = "search";

  static Map<String, OccasionTab> getAvailableTabs(
          [VoidCallback? onSetAsRead]) =>
      {
        unit: OccasionTab(
          key: unit,
          label: OccasionHomeStrings.home,
          icon: Icons.home_outlined,
          activeIcon: Icons.home,
          route: UnitRoute(),
          path: UnitPage.ROUTE,
        ),
        home: OccasionTab(
          key: home,
          label: CommonStrings.schedule,
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month,
          route: ScheduleNavigationRoute(children: [_scheduleRootRoute()]),
          path: EventPage.ROUTE,
        ),
        timetable: OccasionTab(
          key: home,
          label: CommonStrings.schedule,
          icon: Icons.calendar_month_outlined,
          activeIcon: Icons.calendar_month,
          route: TimetableRoute(),
          path: TimetablePage.ROUTE,
        ),
        news: OccasionTab(
          key: news,
          label: OccasionHomeStrings.news,
          icon: Icons.notifications_none_outlined,
          activeIcon: Icons.notifications,
          route: NewsRoute(onSetAsRead: onSetAsRead),
          path: NewsPage.ROUTE,
        ),
        map: OccasionTab(
          key: map,
          label: CommonStrings.map,
          icon: Icons.map_outlined,
          activeIcon: Icons.map,
          route: PublicMapRoute(
            destination: PublicMapPage.overviewDestination,
          ),
          path: MapPage.ROUTE,
        ),
        more: OccasionTab(
          key: more,
          label: OccasionHomeStrings.more,
          icon: Icons.info_outline,
          activeIcon: Icons.info,
          route: InfoRoute(),
          path: InfoPage.ROUTE,
        ),
        user: OccasionTab(
          key: user,
          label: "", // Label dynamically replaced in the navigation bar
          icon: Icons.account_circle_outlined,
          activeIcon: Icons.account_circle,
          route: UserRoute(),
          requiresLogin: true,
          path: UserPage.ROUTE,
        ),
        // "search" opens GlobalSearchDialog on tap (handled in onTap); the
        // route is a never-displayed placeholder so tab/route counts align.
        search: OccasionTab(
          key: search,
          label: SearchStrings.tooltip,
          icon: Icons.search,
          activeIcon: Icons.search,
          route: UserRoute(),
        ),
      };

  static PageRouteInfo _scheduleRootRoute() {
    final feature =
        FeatureService.getFeatureDetails(ScheduleFeature.metaSchedule);
    if (feature is ScheduleFeature) {
      if (feature.scheduleType == ScheduleFeature.scheduleTypeAdvanced) {
        return const ScheduleRoute();
      }
      if (feature.scheduleType == ScheduleFeature.scheduleTypeLight) {
        return const ScheduleLightRoute();
      }
    }
    return const ScheduleBasicRoute();
  }

  static List<PageRouteInfo<dynamic>> getTabRoutes(List<String> tabKeys) {
    return tabKeys.map((key) => getAvailableTabs()[key]!.route).toList();
  }

  Widget buildIcon(BuildContext context, int messageCount,
      String Function() messageCountString) {
    if (key == news) {
      return badges.Badge(
        showBadge: messageCount > 0,
        badgeContent: Text(
          messageCountString(),
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        child: Icon(icon),
      );
    }
    return Icon(icon);
  }

  Widget buildActiveIcon(BuildContext context, int messageCount,
      String Function() messageCountString) {
    if (key == news) {
      return badges.Badge(
        showBadge: messageCount > 0,
        badgeContent: Text(
          messageCountString(),
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        child: Icon(activeIcon),
      );
    }
    return Icon(activeIcon);
  }
}

final class _AutoRouteMapNavigationAdapter implements MapTabNavigationAdapter {
  BuildContext? context;
  TabsRouter? tabsRouter;
  int mapIndex = -1;
  Completer<void>? _visit;
  bool _visitBecameVisible = false;
  int? _originIndex;

  @override
  Future<void> activateMap() {
    final current = context;
    final tabs = tabsRouter;
    if (current == null || !current.mounted || tabs == null) {
      return Future.error(StateError('Occasion map router is not mounted.'));
    }

    final existing = _visit;
    if (existing != null) return existing.future;

    final visit = Completer<void>();
    _visit = visit;
    _visitBecameVisible = false;
    _originIndex = tabs.activeIndex;

    // Navigate on the TabsRouter itself. A path navigation would re-resolve the
    // whole occasion hierarchy and discard the caller's nested stack (such as
    // event/:id), while a root push would create a second occasion shell.
    // Typed navigate() also replaces the existing tab page and remounts its
    // native platform view. Selecting the already registered tab preserves the
    // exact retained host; AutoRoute still publishes its URL/history state.
    if (mapIndex < 0) {
      _visit = null;
      return Future.error(StateError('Occasion map tab is unavailable.'));
    }
    tabs.setActiveIndex(mapIndex);
    return visit.future;
  }

  @override
  Future<void> deactivateMap() async {
    final tabs = tabsRouter;
    final originIndex = _originIndex;
    if (tabs == null || originIndex == null) {
      throw StateError('Public map visit has no origin route.');
    }
    tabs.setActiveIndex(originIndex);
  }

  void setVisible(bool visible) {
    final visit = _visit;
    if (visit == null) return;
    if (visible) {
      _visitBecameVisible = true;
    } else if (_visitBecameVisible) {
      if (!visit.isCompleted) visit.complete();
      _visit = null;
      _visitBecameVisible = false;
      _originIndex = null;
    }
  }

  void dispose() {
    final visit = _visit;
    if (visit != null && !visit.isCompleted) {
      visit.completeError(StateError('Occasion map router was disposed.'));
    }
    _visit = null;
    _visitBecameVisible = false;
    _originIndex = null;
    context = null;
    tabsRouter = null;
    mapIndex = -1;
  }
}
