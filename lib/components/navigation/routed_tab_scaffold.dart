import 'package:fstapp/components/single_data_grid/admin_tab_activity.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/app_panel_helper.dart';
import 'package:fstapp/components/_shared/red_strip_widget.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/theme_config.dart';

/// Return a selected parent section to its first nested tab, keeping the
/// selected object and the route guard for unsaved edits.
Future<void> resetNestedTabs(RoutingController parent, String routeName) async {
  var nested = parent.innerRouterOf<RoutingController>(routeName);
  while (nested != null) {
    if (nested is TabsRouter && nested.stack.isNotEmpty) {
      final first = nested.stack.first.routeData;
      await nested.navigate(PageRouteInfo(first.name,
          args: first.args,
          rawPathParams: first.params.rawMap,
          rawQueryParams: parent.root.urlState.uri.queryParametersAll));
    }
    nested = nested.innerRouterOf<RoutingController>(nested.current.name);
  }
}

/// Presentation metadata. The route, never the label or index, owns identity.
class RoutedTabDefinition {
  final String slug;
  final PageRouteInfo route;
  final String label;
  final IconData icon;
  const RoutedTabDefinition(
      {required this.slug,
      required this.route,
      required this.label,
      required this.icon});
}

class RoutedTabScaffold extends StatelessWidget {
  final List<RoutedTabDefinition> tabs;
  final bool administration;
  final bool reservations;
  final Widget Function(BuildContext, Widget, TabController)? builder;
  const RoutedTabScaffold(
      {super.key,
      required this.tabs,
      this.administration = false,
      this.reservations = false,
      this.builder});

  @override
  Widget build(BuildContext context) {
    context.dependOnInheritedWidgetOfExactType<RouteDataScope>();
    final parentActive = AdminTabActivity.isActive(context);
    if (tabs.isEmpty) return const Center(child: Text('Unavailable'));
    // A disabled, known section is normalized before any child is constructed.
    final pending = context.routeData.pendingChildren;
    final retained =
        context.router.innerRouterOf<TabsRouter>(context.routeData.name);
    final requested =
        pending.isNotEmpty ? pending.first.name : retained?.current.name;
    if (requested != null && !tabs.any((t) => t.route.routeName == requested)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final parent = context.routeData;
        context.router.replace(PageRouteInfo(parent.name,
            args: parent.args,
            rawPathParams: parent.params.rawMap,
            rawQueryParams: parent.queryParams.rawMap,
            initialChildren: [tabs.first.route]));
      });
      return const Center(child: CircularProgressIndicator());
    }
    return AutoTabsRouter.tabBar(
        routes: tabs.map((t) => t.route).toList(),
        physics: const NeverScrollableScrollPhysics(),
        builder: (context, child, controller) {
          child = AdminTabActivity(
              controller: controller,
              routeNames: tabs.map((t) => t.route.routeName).toList(),
              parentActive: parentActive,
              child: child);
          if (builder != null) return builder!(context, child, controller);
          if (administration) {
            final scaffold = Scaffold(
                appBar: AppPanelHelper.buildAdaptiveAdminAppBar(context,
                    activeTabs: tabs, tabController: controller),
                body: SafeArea(top: false, child: child));
            if (!reservations) return scaffold;
            return Column(children: [
              const SafeArea(bottom: false, child: RedStripWidget()),
              Expanded(child: scaffold)
            ]);
          }
          return Column(children: [
            Container(
                color: ThemeConfig.backgroundColor(context),
                alignment: Alignment.centerLeft,
                child: TabBar(
                    controller: controller,
                    onTap: (index) => resetNestedTabs(
                        context.tabsRouter, tabs[index].route.routeName),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: tabs
                        .map((t) =>
                            DataGridHelper.buildTab(context, t.icon, t.label))
                        .toList())),
            Expanded(child: child)
          ]);
        });
  }
}

@RoutePage()
class NavigationNotFoundPage extends StatelessWidget {
  const NavigationNotFoundPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('Not found')));
}
