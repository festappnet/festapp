import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('spot swap uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseTicketCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': <String, dynamic>{},
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
    await commands.swapSpots(1, 2);
    expect(functionName, 'swap_spot_tickets_client_sync_v1');
  });

  test('ticket cancellation uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseTicketCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'cancelledOrderIds': [5],
            'updatedOrders': [
              {'id': 6, 'email': 'owner@example.test'}
            ],
          },
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
    final result = await commands.cancel([1, 2]);
    expect(result.cancelledOrderIds, [5]);
    expect(result.updatedOrders, [(id: 6, email: 'owner@example.test')]);
    expect(functionName, 'storno_tickets_client_sync_v1');
  });
  test('rejected cancellation never returns orders to email', () async {
    final commands = SupabaseTicketCommands.withTransport(
      ClientCommandTransport(
          (name, params) async => {
                'status': 'rejected',
                'code': 403,
                'data': {
                  'updatedOrders': [
                    {'id': 6, 'email': 'owner@example.test'}
                  ]
                },
                'mutation': {
                  'commandId': '00000000-0000-4000-8000-000000000001',
                  'receiptId': '00000000-0000-4000-8000-000000000001',
                  'commitId': null,
                  'replayed': false,
                  'occurredAt': '2026-10-07T10:00:00Z'
                },
                'sync': {'replacements': <Object>[]},
              },
          maxAttempts: 1),
    );
    await expectLater(commands.cancel([1]), throwsStateError);
  });
}
