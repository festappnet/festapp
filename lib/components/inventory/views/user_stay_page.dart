import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/models/spot_model.dart';
import 'package:fstapp/components/inventory/models/inventory_context_model.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/components/inventory/models/user_inventory_bundle.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/inventory/db_inventory_pools.dart';
import 'package:fstapp/data_services/offline_data_service.dart';
import 'package:fstapp/components/offline/offline_banner.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/html/html_view.dart';
import '../../map/map_navigation.dart';

@RoutePage()
class UserStayPage extends StatefulWidget {
  static const ROUTE = "userstay";

  const UserStayPage({super.key});

  @override
  _UserStayPageState createState() => _UserStayPageState();
}

class _UserStayPageState extends State<UserStayPage> {
  Map<InventoryPoolType, List<InventoryContextModel>> _groupedContexts = {};
  Map<InventoryPoolType, String?> _typeDescriptions = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// **Loads data with an offline-first approach.**
  ///
  /// This method first attempts to load and display data from the local cache
  /// for a fast UI response. It then fetches fresh data from the network
  /// to update the view and refresh the cache for future use.
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // 1. Attempt to load and display offline data first.
    // The loading indicator remains active while we fetch fresh data.
    try {
      final offlineBundle = await OfflineDataService.getUserInventoryBundle();
      if (offlineBundle != null && mounted) {
        _processBundle(offlineBundle); // Process and display stale data
      }
    } catch (e) {
      AppLogger.error("Could not load offline user stay data: $e");
      // It's okay to fail here, we proceed to fetch fresh data.
    }

    if (ConnectivityService.isOfflineNotifier.value) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 2. Fetch fresh data from the network.
    try {
      final onlineBundle = await DbInventoryPools.getUserInventory();
      // Save the latest data for future offline use.
      await OfflineDataService.saveUserInventoryBundle(onlineBundle);

      if (mounted) {
        // Process and display the fresh data, replacing the offline view.
        _processBundle(onlineBundle);
      }
    } catch (e) {
      // As requested, fail silently if the online load fails.
      // The user will be left with the offline data if it was available.
      // We still print the error for debugging purposes.
      AppLogger.error("Error loading user inventory from network: $e");
    } finally {
      // 3. Stop the loading indicator after the network attempt is complete.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// **Helper method to process a UserInventoryBundle and update the state.**
  void _processBundle(UserInventoryBundle bundle) {
    // Group only the contexts where the user has assigned spots
    final userContexts = bundle.inventoryContexts
        .where((c) => c.spots != null && c.spots!.isNotEmpty)
        .toList();

    final grouped = groupBy<InventoryContextModel, InventoryPoolType>(
      userContexts,
      (context) => context.inventoryPool!.type,
    );

    final descriptions = <InventoryPoolType, String?>{};
    grouped.forEach((type, contexts) {
      // Sort contexts within each group by date and order
      contexts.sort((a, b) {
        int dateCompare =
            (a.blockDate ?? DateTime(0)).compareTo(b.blockDate ?? DateTime(0));
        if (dateCompare != 0) return dateCompare;
        return (a.order ?? 0).compareTo(b.order ?? 0);
      });

      // Extract unique descriptions for each accommodation type
      for (var context in contexts) {
        final pool = context.inventoryPool;
        if (pool != null && !HtmlHelper.isHtmlEmptyOrNull(pool.description)) {
          descriptions.putIfAbsent(pool.type, () => pool.description);
        }
      }
    });

    if (!mounted) return;
    setState(() {
      _groupedContexts = grouped;
      _typeDescriptions = descriptions;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(InventoryStrings.userStayTitle,
            style: TextStyle(color: ThemeConfig.appBarColorNegative())),
        leading: BackButton(
          color: ThemeConfig.appBarColorNegative(),
          onPressed: () => RouterService.goBack(context),
        ),
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: StylesConfig.appMaxWidth),
                child: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // Show a loading indicator if we are in the initial loading state and have no data yet.
    if (_isLoading && _groupedContexts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show the empty state if loading is complete and there's still nothing to show.
    if (!_isLoading && _groupedContexts.isEmpty) {
      return _buildEmptyState();
    }

    // Display the data (either offline or updated online data).
    final sortedTypes = _groupedContexts.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: sortedTypes.length,
      itemBuilder: (context, index) {
        final type = sortedTypes[index];
        final contextsForType = _groupedContexts[type]!;
        final description = _typeDescriptions[type];
        final pool = contextsForType.isNotEmpty
            ? contextsForType.first.inventoryPool
            : null;
        if (pool == null) return const SizedBox.shrink();

        final titleText = pool.title ?? type.displayName;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The ListTile and separate Padding for the description have been replaced
            // with a single Column inside one Padding widget to ensure consistent alignment.
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The Wrap containing the title and chip is now here.
                  Wrap(
                    spacing: 20.0,
                    runSpacing: 4.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        titleText,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (pool.place != null)
                        ActionChip(
                          avatar: Icon(Icons.place_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.secondary),
                          label: Text(pool.place!.title!),
                          onPressed: () {
                            MapNavigation.openPlace(
                              context,
                              pool.place!.id!,
                            );
                          },
                          shape: StadiumBorder(
                              side: BorderSide(
                                  color: Theme.of(context).dividerColor)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          backgroundColor: Colors.transparent,
                          labelStyle: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                  // The description is added conditionally to the same Column.
                  if (description != null) ...[
                    const SizedBox(height: 12.0),
                    HtmlView(
                      html: description,
                      isSelectable: true,
                    ),
                    const SizedBox(height: 12.0),
                  ]
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Wrap(
                spacing: 12.0,
                runSpacing: 12.0,
                children: contextsForType
                    .map(
                        (contextModel) => _buildContextCard(contextModel, type))
                    .toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildContextCard(
      InventoryContextModel contextModel, InventoryPoolType type) {
    final spots = contextModel.spots ?? [];
    final cardWidth =
        MediaQuery.of(context).size.width > 480 ? 320.0 : double.infinity;
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contextModel.getContextTitle(context),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (spots.isNotEmpty)
              const Divider(height: 1, indent: 16, endIndent: 16),
            if (spots.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 1.0, vertical: 4.0),
                child: Column(
                  children:
                      spots.map((spot) => _buildSpotTile(spot, type)).toList(),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildSpotTile(SpotModel spot, InventoryPoolType type) {
    final resourceTitle =
        spot.resource?.title ?? InventoryStrings.userStayUnassignedRoom;
    final spotTitle = spot.title;
    final hasSpotTitle = spotTitle != null && spotTitle.isNotEmpty;
    final theme = Theme.of(context);

    return ListTile(
      visualDensity: VisualDensity.compact,
      title: Row(
        // Use CrossAxisAlignment.start to align the icon with the top of the text column.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(type.icon, color: theme.colorScheme.secondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            // Use a Column to ensure the title and subtitle are perfectly aligned vertically.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  resourceTitle,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasSpotTitle)
                  // No need for extra padding here, alignment is handled by the Column.
                  Text(spotTitle, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
      // The subtitle is now part of the title structure, so this can be null.
      subtitle: null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hotel, size: 50, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              InventoryStrings.userStayEmptyStateMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
