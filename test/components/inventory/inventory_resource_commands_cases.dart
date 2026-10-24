import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/inventory/inventory_commands.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('resource save carries its optimistic version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 5,
            'resource': {
              'id': 9,
              'title': 'Room',
              'capacity': 2,
              'inventory_pool': 3,
              'aggregate_version': 5,
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final result = await commands.saveResource(
      7,
      ResourceModel(
        id: 9,
        title: 'Room',
        capacity: 2,
        inventoryPoolId: 3,
        aggregateVersion: 4,
      ),
    );

    expect(functionName, 'save_resource_client_sync_v1');
    expect(parameters['p_expected_version'], 4);
    expect(result.aggregateVersion, 5);
  });

  test('resource delete uses the loaded version', () async {
    late Map<String, dynamic> parameters;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'version': 3, 'resource': null},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.deleteResource(
      7,
      ResourceModel(
        id: 9,
        inventoryPoolId: 3,
        aggregateVersion: 3,
      ),
    );

    expect(parameters['p_resource'], 9);
    expect(parameters['p_expected_version'], 3);
  });

  test('pool delete uses the loaded bundle version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'version': 8, 'pool': null},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.deletePool(7, 3, 8);

    expect(functionName, 'delete_inventory_pool_client_sync_v1');
    expect(parameters['p_expected_version'], 8);
  });
}
