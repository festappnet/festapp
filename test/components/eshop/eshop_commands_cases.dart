import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/supabase_eshop_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

Map<String, dynamic> productScope() => {
  'p_occasion': 7,
  'p_organization': 3,
  'p_unit': 2,
};

void main() {
  test('product save uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        if (name == 'manage_product') {
          expect(params['p_organization'], 3);
          expect(params['p_unit'], 2);
          expect(params['p_occasion'], 7);
        }
        return {
          'status': 'applied',
          'code': 200,
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': '00000000-0000-4000-8000-000000000001',
            'replayed': false,
            'occurredAt': '2026-10-20T10:00:00Z',
          },
          'data': {'productId': 9, 'aggregate_version': 1},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
      productScope: productScope,
    );
    final saved = await commands.saveProduct({'title': 'Lunch'});
    expect(saved.id, 9);
    expect(saved.aggregateVersion, 1);
    expect(functionName, 'manage_product');
  });

  test(
    'existing product save cannot replace its missing original baseline',
    () async {
      var calls = 0;
      final commands = SupabaseEshopCommands.withTransport(
        ClientCommandTransport((_, __) async {
          calls++;
          return {};
        }, maxAttempts: 1),
        productScope: productScope,
      );
      await expectLater(
        commands.saveProduct({'id': 9, 'title': 'Changed'}),
        throwsArgumentError,
      );
      expect(calls, 0);
    },
  );

  test('product delete uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        expect(params['p_product'], {'id': 9, 'expected_aggregate_version': 7});
        expect(params['p_action'], 'delete');
        expect(params['p_occasion'], 7);
        expect(params['p_organization'], 3);
        return {
          'status': 'applied',
          'code': 200,
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': '00000000-0000-4000-8000-000000000001',
            'replayed': false,
            'occurredAt': '2026-10-20T10:00:00Z',
          },
          'data': {'productId': 9, 'aggregate_version': 1},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
      productScope: productScope,
    );
    await commands.deleteProduct(9, expectedVersion: 7);
    expect(functionName, 'manage_product');
  });

  test('product context update uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        expect(params['p_action'], 'contexts');
        expect(params['p_product'], {
          'id': 4,
          'expected_aggregate_version': 2,
          'inventory_contexts': [
            {'inventory_context_id': 8, 'quantity': 1},
            {'inventory_context_id': 9, 'quantity': 2},
          ],
        });
        return {
          'status': 'applied',
          'code': 200,
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': '00000000-0000-4000-8000-000000000001',
            'replayed': false,
            'occurredAt': '2026-10-20T10:00:00Z',
          },
          'data': {'productId': 4},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
      productScope: productScope,
    );
    await commands.updateProductInventoryContexts(4, [
      {'inventory_context_id': 9, 'quantity': 2},
      {'inventory_context_id': 8, 'quantity': 1},
    ], expectedVersion: 2);
    expect(functionName, 'manage_product');
  });

  test('ticket products use their dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': '00000000-0000-4000-8000-000000000001',
            'replayed': false,
            'occurredAt': '2026-10-20T10:00:00Z',
          },
          'data': {'code': 200},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
      productScope: productScope,
    );
    await commands.updateTicketProducts(5, [
      {'id': 9, 'price': 100},
    ]);
    expect(functionName, 'update_ticket_products_client_sync_v1');
  });
}
