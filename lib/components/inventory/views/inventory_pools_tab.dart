import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/inventory/models/inventory_pools_list_bundle.dart';
import 'package:fstapp/components/inventory/db_inventory_pools.dart';
import 'package:fstapp/styles/styles_config.dart';

import '../models/inventory_pool_model.dart';
import 'inventory_pool_card.dart';
import 'inventory_pool_creation_helper.dart';
import 'package:fstapp/app_router.gr.dart';
import 'inventory_strings.dart';

@RoutePage(name: 'InventoryPoolsListRoute')
class InventoryPoolsTab extends StatefulWidget {
  const InventoryPoolsTab({super.key});

  @override
  _InventoryPoolsTabState createState() => _InventoryPoolsTabState();
}

class _InventoryPoolsTabState extends State<InventoryPoolsTab> {
  InventoryPoolsListBundle? _bundle;
  bool _isLoading = true;

  String? _previousOccasionLink;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newOccasionLink = context.routeData.inheritedPathParams
        .get(AppRouter.linkFormatted, null);

    if (newOccasionLink != null && newOccasionLink != _previousOccasionLink) {
      _previousOccasionLink = newOccasionLink;
      loadData(newOccasionLink);
    }
  }

  Future<void> loadData(String occasionLink,
      {bool isRefresh = false, int? newSelectedGroupId}) async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final newBundle =
          await DbInventoryPools.getInventoryPoolsByOccasionLink(occasionLink);
      if (!mounted || _previousOccasionLink != occasionLink) return;
      _bundle = newBundle;

      if (_bundle != null) {
        // Link objects for easier access
        for (var context in _bundle!.inventoryContexts) {
          context.inventoryPool = _bundle!.pools
              .firstWhereOrNull((group) => group.id == context.inventoryPoolId);
        }
        for (var spot in _bundle!.spots) {
          spot.inventoryContext = _bundle!.inventoryContexts.firstWhereOrNull(
              (context) => context.id == spot.inventoryContextId);
        }
      }
    } catch (e) {
      // Error fetching capacity groups bundle
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(InventoryStrings.tabErrorRefresh),
              backgroundColor: Colors.red),
        );
      }
      // On error, do not clear the bundle to avoid a full UI reset
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _handleCardTap(InventoryPoolModel pool) {
    context.router.push(InventoryPoolDetailRoute(poolId: pool.id!.toString()));
  }

  Future<void> _handleCreateNew() async {
    if (_bundle?.occasion.id != null) {
      await InventoryPoolCreationHelper.showCreatePoolDialog(
        context: context,
        occasionId: _bundle!.occasion.id!,
        onPoolCreated: () {
          if (_previousOccasionLink != null) loadData(_previousOccasionLink!);
        },
      );
    }
  }

  Widget _buildGroupsGrid() {
    if (_bundle == null) {
      return Center(child: Text(InventoryStrings.tabNoData));
    }
    return RefreshIndicator(
      onRefresh: () => loadData(_previousOccasionLink!),
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 480,
                mainAxisExtent: 210,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final group = _bundle!.pools[index];
                  final groupContexts = _bundle!.inventoryContexts
                      .where((c) => c.inventoryPoolId == group.id)
                      .toList();
                  final contextIds = groupContexts.map((c) => c.id).toSet();
                  final groupSpots = _bundle!.spots
                      .where((s) => contextIds.contains(s.inventoryContextId))
                      .toList();

                  return InventoryPoolCard(
                    pool: group,
                    contexts: groupContexts,
                    spots: groupSpots,
                    onTap: () => _handleCardTap(group),
                  );
                },
                childCount: _bundle!.pools.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(InventoryStrings.tabTitle),
        elevation: 0,
        toolbarHeight: 44.0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(InventoryStrings.tabCreateNewGroup),
              onPressed: _handleCreateNew,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(StylesConfig.commonRoundness),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildGroupsGrid(),
    );
  }
}
