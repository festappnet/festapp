import 'package:fstapp/components/inventory/models/inventory_pool_bundle.dart';
import 'package:fstapp/components/inventory/models/inventory_pools_list_bundle.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/inventory/models/user_inventory_bundle.dart';
import 'package:fstapp/components/inventory/inventory_commands.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbInventoryPools {
  static final _supabase = Supabase.instance.client;
  static InventoryCommands get _commands =>
      SupabaseInventoryCommands(_supabase);

  static Future<UserInventoryBundle> getUserInventory() async {
    // 1. Call the RPC function.
    final response = await _supabase.rpc('get_user_inventory');

    // 2. Deserialize the response into a fully linked bundle.
    return UserInventoryBundle.fromJson(response);
  }

  static Future<InventoryPoolsListBundle> getInventoryPoolsByOccasionLink(
      String occasionLink) async {
    final response = await _supabase.rpc(
      'get_inventory_pools_by_occasion_link',
      params: {'p_occasion_link': occasionLink},
    );

    if (response is Map &&
        response.containsKey('code') &&
        response['code'] != 200) {
      throw Exception(
          "Failed to fetch inventory pools: ${response['message']}");
    }
    final bundle = InventoryPoolsListBundle.fromJson(response);
    final poolMap = {for (var p in bundle.pools) p.id: p};
    final contextMap = {for (var c in bundle.inventoryContexts) c.id: c};
    for (final context in bundle.inventoryContexts) {
      context.inventoryPool = poolMap[context.inventoryPoolId];
    }
    for (final spot in bundle.spots) {
      if (spot.inventoryContextId != null) {
        spot.inventoryContext = contextMap[spot.inventoryContextId];
      }
    }
    return bundle;
  }

  static Future<InventoryPoolBundle> getInventoryPoolBundle(int poolId) async {
    final response = await _supabase.rpc(
      'get_inventory_pool_bundle',
      params: {'p_inventory_pool_id': poolId},
    );

    if (response is Map &&
        response.containsKey('code') &&
        response['code'] != 200) {
      throw Exception(
          "Failed to fetch inventory pool bundle: ${response['message']}");
    }

    return InventoryPoolBundle.fromJson(response);
  }

  static Future<InventoryPoolBundle> updateInventoryPoolBundle(
      InventoryPoolBundle bundle) async {
    return _commands.savePool(bundle);
  }

  static Future<void> deleteInventoryPool(
    int poolId, {
    int expectedVersion = 0,
  }) async {
    await _commands.deletePool(
      RightsService.currentOccasionId()!,
      poolId,
      expectedVersion,
    );
    return;
  }

  static Future<void> deleteResource(ResourceModel resource) async {
    await _commands.deleteResource(
      RightsService.currentOccasionId()!,
      resource,
    );
    return;
  }

  static Future<void> updateResource(ResourceModel resource) async {
    final saved = await _commands.saveResource(
      RightsService.currentOccasionId()!,
      resource,
    );
    resource.id = saved.id;
    resource.aggregateVersion = saved.aggregateVersion;
    return;
  }
}
