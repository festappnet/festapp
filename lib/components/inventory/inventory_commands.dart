import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_bundle.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:festapp_core/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class InventoryCommands {
  Future<InventoryPoolBundle> savePool(InventoryPoolBundle bundle);
  Future<void> deletePool(int occasionId, int poolId, int expectedVersion);
  Future<ResourceModel> saveResource(int occasionId, ResourceModel resource);
  Future<void> deleteResource(int occasionId, ResourceModel resource);
}

class SupabaseInventoryCommands implements InventoryCommands {
  SupabaseInventoryCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client);

  SupabaseInventoryCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<void> deletePool(
    int occasionId,
    int poolId,
    int expectedVersion,
  ) async {
    await _invoke('delete_inventory_pool_client_sync_v1', {
      'p_occasion': occasionId,
      'p_pool': poolId,
      'p_expected_version': expectedVersion,
    });
  }

  @override
  Future<ResourceModel> saveResource(
    int occasionId,
    ResourceModel resource,
  ) async {
    final response = await _invoke('save_resource_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version':
          resource.id == null ? null : resource.aggregateVersion,
      'p_resource': resource.toJson(),
    });
    final raw = response.data['resource'];
    if (raw is! Map) {
      throw const FormatException('Resource command omitted resource');
    }
    return ResourceModel.fromJson(raw.cast<String, dynamic>());
  }

  @override
  Future<void> deleteResource(int occasionId, ResourceModel resource) async {
    final id = resource.id;
    if (id == null) throw ArgumentError('Deleting a resource requires its ID');
    await _invoke('delete_resource_client_sync_v1', {
      'p_occasion': occasionId,
      'p_resource': id,
      'p_expected_version': resource.aggregateVersion,
    });
  }

  @override
  Future<InventoryPoolBundle> savePool(InventoryPoolBundle bundle) async {
    final occasionId = bundle.pool.occasionId;
    if (occasionId == null) {
      throw ArgumentError.value(occasionId, 'bundle.pool.occasionId');
    }
    final raw = await _transport.invoke('save_inventory_pool_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version':
          bundle.pool.id == null ? null : bundle.aggregateVersion,
      'p_bundle': bundle.toJson(),
    });
    final response = ClientCommandResponse.from(raw);
    if (response.status == 'conflict') {
      throw StateError('Inventory pool was changed by another editor');
    }
    if (response.status == 'rejected') {
      throw StateError('Inventory pool save was rejected');
    }
    await applyClientCommandReplacements(response);
    final data = response.data;
    return InventoryPoolBundle.fromJson(
        (data['bundle'] as Map).cast<String, dynamic>());
  }

  Future<ClientCommandResponse> _invoke(
    String name,
    Map<String, dynamic> parameters,
  ) async {
    final response = ClientCommandResponse.from(
      await _transport.invoke(name, parameters),
    );
    if (response.status == 'conflict') {
      throw StateError('Inventory aggregate was changed by another editor');
    }
    if (response.status == 'rejected') {
      throw StateError('Inventory command was rejected');
    }
    await applyClientCommandReplacements(response);
    return response;
  }
}
