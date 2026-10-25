import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/breadcrumb_row.dart';
import 'package:fstapp/styles/styles_config.dart';
import '../models/inventory_pools_list_bundle.dart';
import '../models/inventory_pool_model.dart';
import 'package:fstapp/components/navigation/retained_draft_guard.dart';
import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/inventory/views/spot_management_view.dart';
import 'inventory_pool_settings_view.dart';
import 'inventory_pool_creation_helper.dart';
import 'inventory_strings.dart';
import 'resource_editor_view.dart';
import '../db_inventory_pools.dart';

@RoutePage()
class InventoryPoolDetailPage extends StatefulWidget {
  final String poolId;
  final Future<InventoryPoolsListBundle> Function(String)? loadPools;
  const InventoryPoolDetailPage(
      {super.key, @PathParam('poolId') required this.poolId, this.loadPools});
  @override
  State<InventoryPoolDetailPage> createState() =>
      _InventoryPoolDetailPageState();
}

class _InventoryPoolDetailPageState extends State<InventoryPoolDetailPage> {
  bool _ready = false;
  bool _failed = false;
  int _generation = 0;
  String? _link;
  int? _occasionId;
  List<InventoryPoolModel> _pools = [];
  final _occupancyKey = GlobalKey<SpotManagementViewState>();
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final link = context.routeData.inheritedPathParams
        .getString(AppRouter.linkFormatted);
    if (_link != link) {
      _link = link;
      _load();
    }
  }

  @override
  void didUpdateWidget(InventoryPoolDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poolId != widget.poolId) {
      _ready = false;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final link = _link!;
    if (int.tryParse(widget.poolId) == null) {
      setState(() => _failed = true);
      return;
    }
    try {
      final objects = await (widget.loadPools ??
          DbInventoryPools.getInventoryPoolsByOccasionLink)(link);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pools = objects.pools;
        _occasionId = objects.occasion.id;
        _ready = RightsService.currentLink == link &&
            objects.pools.any((p) => p.id == int.tryParse(widget.poolId));
        _failed = !_ready;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    }
  }

  void _updated() {
    _occupancyKey.currentState?.fetchGridData();
    _load();
  }

  void _back() {
    RetainedDraftGuard.instance.leaveOwner(
        context,
        () => context.router.replaceAll([
              PageRouteInfo(InventoryPoolsListRoute.name, rawQueryParams: {
                ...context.router.root.urlState.uri.queryParametersAll,
                'list': 'true',
              })
            ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed)
      return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.arrow_back), onPressed: _back)),
        body: const Center(child: Text('Not found or access denied')),
      );
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return InventoryPoolRouteScope(
        identity: int.parse(widget.poolId),
        onDeleted: _back,
        onUpdated: _updated,
        occupancyKey: _occupancyKey,
        child: Scaffold(
            appBar: AppBar(
                automaticallyImplyLeading: false,
                centerTitle: false,
                elevation: 0,
                toolbarHeight: 44,
                title: _buildBreadcrumbs(),
                actions: [
                  if (!RightsService.isDemoReadOnly && _occasionId != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 4),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(MediaQuery.sizeOf(context).width < 900
                              ? CommonStrings.create
                              : InventoryStrings.tabCreateNewGroup),
                          onPressed: () => RetainedDraftGuard.instance
                              .leaveOwner(
                                  context,
                                  () => InventoryPoolCreationHelper
                                      .showCreatePoolDialog(
                                          context: context,
                                          occasionId: _occasionId!,
                                          onPoolCreated: _back)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor:
                                  Theme.of(context).colorScheme.onPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      StylesConfig.commonRoundness))),
                        )),
                  const SizedBox(width: 8),
                ]),
            body: AutoRouter(key: ValueKey(widget.poolId))));
  }

  Widget _buildBreadcrumbs() {
    final color = Theme.of(context).appBarTheme.foregroundColor ?? Colors.white;
    final selected =
        _pools.firstWhere((pool) => pool.id.toString() == widget.poolId);
    final title = Text(selected.title ?? '',
        style: TextStyle(
            fontSize: 16,
            color: color,
            fontWeight:
                _pools.length <= 1 ? FontWeight.bold : FontWeight.normal));
    void resetTabs() =>
        resetNestedTabs(context.router, InventoryPoolDetailRoute.name);
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: BreadcrumbRow(children: [
          InkWell(
              onTap: _back,
              borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IgnoreBaseline(
                    child:
                        Icon(Icons.grid_view_outlined, size: 20, color: color)),
                const SizedBox(width: 6),
                Text(InventoryStrings.tabTitle,
                    style: TextStyle(fontSize: 16, color: color)),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text('/',
                  style: TextStyle(
                      fontSize: 14, color: color.withValues(alpha: .4)))),
          if (_pools.length <= 1)
            InkWell(onTap: resetTabs, child: title)
          else
            PopupMenuButton<InventoryPoolModel>(
                elevation: 0,
                onSelected: (pool) {
                  if (pool.id == selected.id) {
                    resetTabs();
                  } else {
                    RetainedDraftGuard.instance.leaveOwner(
                        context,
                        () => context.router.navigate(InventoryPoolDetailRoute(
                                poolId: pool.id.toString(),
                                children: const [
                                  InventoryPoolTabsRoute(
                                      children: [InventoryPoolOccupancyRoute()])
                                ])));
                  }
                },
                itemBuilder: (_) => _pools
                    .map((pool) => PopupMenuItem(
                        value: pool,
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(pool.title ?? ''),
                              if (pool.id == selected.id)
                                Icon(Icons.check,
                                    color:
                                        Theme.of(context).colorScheme.primary)
                            ])))
                    .toList(),
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      title,
                      const SizedBox(width: 8),
                      Transform.scale(
                          scaleY: .8,
                          child: Icon(Icons.unfold_more_rounded,
                              size: 20, color: color.withValues(alpha: .7))),
                    ]))),
        ]));
  }
}

class InventoryPoolRouteScope extends InheritedWidget {
  final int identity;
  final GlobalKey<SpotManagementViewState> occupancyKey;
  final VoidCallback onDeleted;
  final VoidCallback onUpdated;
  const InventoryPoolRouteScope(
      {super.key,
      required this.identity,
      required this.onDeleted,
      required this.onUpdated,
      required this.occupancyKey,
      required super.child});
  static InventoryPoolRouteScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InventoryPoolRouteScope>()!;
  @override
  bool updateShouldNotify(InventoryPoolRouteScope oldWidget) =>
      oldWidget.identity != identity;
}

@RoutePage(name: 'InventoryPoolTabsRoute')
class InventoryPoolDetailView extends StatelessWidget {
  const InventoryPoolDetailView({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.occupancy,
          route: const InventoryPoolOccupancyRoute(),
          label: InventoryStrings.detailTabOccupancy,
          icon: Icons.grid_view),
      RoutedTabDefinition(
          slug: NavigationPaths.rooms,
          route: const InventoryPoolRoomsRoute(),
          label: InventoryStrings.detailTabRooms,
          icon: Icons.house_siding),
      RoutedTabDefinition(
          slug: NavigationPaths.settings,
          route: const InventoryPoolSettingsRoute(),
          label: InventoryStrings.detailTabSettings,
          icon: Icons.settings),
    ]);
  }
}

@RoutePage()
class InventoryPoolOccupancyPage extends StatelessWidget {
  const InventoryPoolOccupancyPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = InventoryPoolRouteScope.of(context);
    return SpotManagementView(
        key: scope.occupancyKey, inventoryPoolId: scope.identity);
  }
}

@RoutePage()
class InventoryPoolRoomsPage extends StatelessWidget {
  const InventoryPoolRoomsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = InventoryPoolRouteScope.of(context);
    return ResourceEditorView(inventoryPoolId: scope.identity);
  }
}

@RoutePage()
class InventoryPoolSettingsPage extends StatelessWidget {
  const InventoryPoolSettingsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final scope = InventoryPoolRouteScope.of(context);
    return InventoryPoolSettingsView(
        poolId: scope.identity,
        onPoolUpdated: scope.onUpdated,
        onPoolDeleted: scope.onDeleted);
  }
}
