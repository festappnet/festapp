import 'package:fstapp/app_config.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/inventory/models/standing_inventory_preparation.dart';
import 'package:fstapp/data_services/client_sync/client_command_replacements.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_bundle.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:festapp_core/sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class InventoryCommands {
  Future<StandingInventoryPreparation> prepareStanding(
      ProductModel product, int capacity,
      {required int organizationId, int? unitId});
  Future<InventoryPoolBundle> savePool(InventoryPoolBundle bundle);
  Future<void> deletePool(int occasionId, int poolId, int expectedVersion);
  Future<ResourceModel> saveResource(int occasionId, ResourceModel resource);
  Future<void> deleteResource(int occasionId, ResourceModel resource);
}

class SupabaseInventoryCommands implements InventoryCommands {
  SupabaseInventoryCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client, durable: true);

  SupabaseInventoryCommands.withTransport(this._transport);

  final ClientCommandTransport _transport;

  @override
  Future<StandingInventoryPreparation> prepareStanding(
      ProductModel product, int capacity,
      {required int organizationId, int? unitId}) async {
    if (product.id == null || product.occasion == null) {
      throw ArgumentError('Saved product and occasion required');
    }
    final response = await _invoke('prepare_standing_inventory', {
      'p_occasion': product.occasion,
      'p_organization': organizationId,
      'p_unit': unitId,
      'p_product_id': product.id,
      'p_expected_version': product.aggregateVersion,
      'p_capacity': capacity,
    });
    return StandingInventoryPreparation.fromJson(response.data);
  }

  @override
  Future<void> deletePool(
    int occasionId,
    int poolId,
    int expectedVersion,
  ) async {
    await _manage(occasionId, 'delete_pool', {
      'id': poolId,
      'expectedVersion': expectedVersion,
    });
  }

  @override
  Future<ResourceModel> saveResource(
    int occasionId,
    ResourceModel resource,
  ) async {
    final response = await _manage(occasionId, 'save_resource', {
      'expectedVersion':
          resource.id == null ? null : resource.aggregateVersion,
      'resource': resource.toJson(),
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
    await _manage(occasionId, 'delete_resource', {
      'id': id,
      'expectedVersion': resource.aggregateVersion,
    });
  }

  @override
  Future<InventoryPoolBundle> savePool(InventoryPoolBundle bundle) async {
    final occasionId = bundle.pool.occasionId;
    if (occasionId == null) {
      throw ArgumentError.value(occasionId, 'bundle.pool.occasionId');
    }
    final response = await _manage(occasionId, 'save_pool', {
      'expectedVersion': bundle.pool.id == null ? null : bundle.aggregateVersion,
      'bundle': bundle.toJson(),
    });
    final data = response.data;
    return InventoryPoolBundle.fromJson(
        (data['bundle'] as Map).cast<String, dynamic>());
  }

  Future<ClientCommandResponse> _manage(
      int occasionId, String action, Map<String, dynamic> payload) =>
      _invoke('manage_inventory', {
        'p_occasion': occasionId,
        'p_organization': AppConfig.organization,
        'p_unit': RightsService.currentUnit()?.id,
        'p_action': action,
        'p_payload': payload,
        'p_editor': true,
      });

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
