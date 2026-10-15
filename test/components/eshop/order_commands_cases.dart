import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/order_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('order delete uses its dedicated command RPC', () async {
    late String functionName;
    late Map<String, dynamic> sent;
    final commands = SupabaseOrderCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        sent = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'orderId': 5},
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
    await commands.delete(5);
    expect(functionName, 'delete_order_client_sync_v1');
    expect(sent['p_order'], 5);
    expect(sent.containsKey('order_symbol'), isFalse);
  });

  test('order cancellation uses its dedicated command RPC', () async {
    late String functionName;
    late Map<String, dynamic> sent;
    final commands = SupabaseOrderCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        sent = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'orderId': 5},
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
    await commands.cancel(5);
    expect(functionName, 'storno_order_client_sync_v1');
    expect(sent['p_order'], 5);
    expect(sent.containsKey('order_symbol'), isFalse);
  });
}
