import 'package:fstapp/components/inventory/models/inventory_pool_bundle.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_model.dart';
import 'package:fstapp/app_config.dart';
import 'dart:async';
import 'package:festapp_core/eshop.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/inventory/inventory_commands.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test(
      'standing preparation retries one command and consumes saved versions without reload',
      () async {
    final calls = <Map<String, dynamic>>[];
    var lose = true;
    final commands = SupabaseInventoryCommands.withTransport(
        ClientCommandTransport((name, params) async {
      expect(name, 'prepare_standing_inventory');
      calls.add(params);
      if (lose) {
        lose = false;
        throw TimeoutException('lost');
      }
      return {
        'mutation': commandResponseFixture(
            params['p_command_id'] as String)['mutation'],
        'status': 'applied',
        'code': 200,
        'data': {
          'product': {
            'id': 9,
            'occasion': 7,
            'type': 'spot',
            'aggregate_version': 4,
            'title': 'Standing',
            'price': 100,
            'form_ids': [10],
            'inventory_contexts': [
              {'inventory_context_id': 6, 'quantity': 1}
            ]
          },
          'forms': [
            {'id': 10, 'title': 'Registration'}
          ],
          'pool': {
            'id': 5,
            'occasion': 7,
            'title': 'Standing stock',
            'sellable_capacity': 25
          },
          'context': {'id': 6, 'inventory_pool': 5, 'title': 'Standing'},
          'resource': {
            'id': 8,
            'inventory_pool': 5,
            'title': 'Supply',
            'capacity': 25,
            'aggregate_version': 1
          },
          'readAt': '2026-10-23T10:00:00Z',
        },
        'sync': {'replacements': <Object>[]},
      };
    }));
    final saved = await commands.prepareStanding(
        ProductModel(id: 9, occasion: 7, aggregateVersion: 3), 25,
        organizationId: 2, unitId: 1);
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls[0]['p_expected_version'], 3);
    expect(calls[0]['p_capacity'], 25);
    expect(saved.product.aggregateVersion, 4);
    expect(saved.product.occasion, 7);
    expect(saved.product.formTitles, 'Registration');
    expect(saved.product.includedInventories.single.inventoryContextId, 6);
    expect(saved.context.inventoryPool!.id, 5);
    expect(saved.resource.aggregateVersion, 1);
  });

  test('resource save carries its optimistic version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'mutation': commandResponseFixture(
              params['p_command_id'] as String)['mutation'],
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

    expect(functionName, 'manage_inventory');
    expect(parameters['p_action'], 'save_resource');
    expect(parameters['p_occasion'], 7);
    expect(parameters['p_organization'], AppConfig.organization);
    expect(parameters['p_editor'], true);
    expect(parameters['p_payload']['expectedVersion'], 4);
    expect(result.aggregateVersion, 5);
  });

  test('resource delete uses the loaded version', () async {
    late Map<String, dynamic> parameters;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        parameters = params;
        return {
          'mutation': commandResponseFixture(
              params['p_command_id'] as String)['mutation'],
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

    expect(parameters['p_payload']['id'], 9);
    expect(parameters['p_payload']['expectedVersion'], 3);
  });

  test('pool delete uses the loaded bundle version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'mutation': commandResponseFixture(
              params['p_command_id'] as String)['mutation'],
          'status': 'applied',
          'code': 200,
          'data': {'version': 8, 'pool': null},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.deletePool(7, 3, 8);

    expect(functionName, 'manage_inventory');
    expect(parameters['p_action'], 'delete_pool');
    expect(parameters['p_payload']['expectedVersion'], 8);
  });

  test('pool save retries identical scoped intent and consumes authoritative editor version', () async {
    final calls = <Map<String, dynamic>>[];
    var lost = true;
    final commands = SupabaseInventoryCommands.withTransport(
      ClientCommandTransport((name, params) async {
        expect(name, 'manage_inventory');
        calls.add(params);
        if (lost) {lost = false; throw TimeoutException('response lost');}
        return commandResponseFixture(params['p_command_id'] as String, data: {
          'version': 5,
          'bundle': {
            'pool': {'id': 3, 'occasion': 7, 'title': 'Saved'},
            'contexts': <Object>[],
            'aggregate_version': 5,
          }
        });
      }),
    );
    final result = await commands.savePool(InventoryPoolBundle(
      pool: InventoryPoolModel(id: 3, occasionId: 7, title: 'Saved'),
      aggregateVersion: 4,
    ));
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls[0]['p_action'], 'save_pool');
    expect(calls[0]['p_payload']['expectedVersion'], 4);
    expect(calls[0]['p_payload']['bundle']['contexts'], isNull);
    expect(calls[0]['p_editor'], true);
    expect(result.pool.id, 3);
    expect(result.aggregateVersion, 5);
  });

}
