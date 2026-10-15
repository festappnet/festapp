import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/eshop/supabase_eshop_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test(
      'product adapter retains exact legacy RPC payloads when sync is not selected',
      () async {
    final requests = <http.Request>[];
    final client = SupabaseClient('https://fixture.invalid', 'fixture',
        httpClient: MockClient((request) async {
      requests.add(request);
      return http.Response(
          request.url.path.endsWith('/update_product') ? '7' : 'null', 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    addTearDown(client.dispose);
    final commands = SupabaseEshopCommands(client, useClientSync: () => false);
    final product = {
      'id': 7,
      'data': {'unknown': false}
    };
    expect(await commands.saveProduct(product), 7);
    await commands.updateProductInventoryContexts(7, [
      {'inventory_context_id': 9, 'quantity': 2}
    ]);
    await commands.deleteProduct(7);
    expect(requests.map((request) => request.url.path), [
      '/rest/v1/rpc/update_product',
      '/rest/v1/rpc/update_product_inventory_contexts',
      '/rest/v1/rpc/delete_product',
    ]);
    expect(requests.map((request) => jsonDecode(request.body)), [
      {'p_input': product},
      {
        'p_product_id': 7,
        'p_contexts': [
          {'inventory_context_id': 9, 'quantity': 2}
        ]
      },
      {'p_product_id': 7},
    ]);
  });
  test('product save uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseEshopCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': {'productId': 9},
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
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': {'productId': 9},
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
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': {'productId': 4},
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
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': {'code': 200},
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
