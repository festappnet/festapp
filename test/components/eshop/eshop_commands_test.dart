import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/eshop_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('product save uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'productId': 9},
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    expect(await commands.saveProduct({'title': 'Lunch'}), 9);
    expect(functionName, 'update_product_client_sync_v1');
  });

  test('product delete uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'productId': 9},
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.deleteProduct(9);
    expect(functionName, 'delete_product_client_sync_v1');
  });

  test('product context update uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'productId': 4},
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.updateProductInventoryContexts(4, [
      {'inventory_context_id': 8, 'quantity': 1},
    ]);
    expect(
      functionName,
      'update_product_inventory_contexts_client_sync_v1',
    );
  });

  test('ticket products use their dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'code': 200},
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.updateTicketProducts(5, [
      {'id': 9, 'price': 100},
    ]);
    expect(functionName, 'update_ticket_products_client_sync_v1');
  });
}
