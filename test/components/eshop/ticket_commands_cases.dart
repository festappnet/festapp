import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
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
          'mutation': {
            'commandId': '00000000-0000-4000-8000-000000000001',
            'receiptId': '00000000-0000-4000-8000-000000000001',
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': <String, dynamic>{},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.swapSpots(1, 2);
    expect(functionName, 'swap_spot_tickets_client_sync_v1');
  });

  test('temporary hold release uses the authenticated receipt command',
      () async {
    final calls = <String>[];
    final commands = SupabaseTicketCommands.withTransport(
        ClientCommandTransport((name, params) async {
      calls.add(name);
      expect(params['p_spots'], [17]);
      expect(params['p_command_id'], isNotEmpty);
      return {
        'mutation': {
          'commandId': params['p_command_id'],
          'receiptId': params['p_command_id'],
          'commitId': null,
          'replayed': false,
          'occurredAt': '2026-10-15T10:00:00Z'
        },
        'status': 'applied',
        'code': 200,
        'data': {
          'spotIds': [17, 18]
        },
        'sync': {'replacements': <Object>[]},
      };
    }, maxAttempts: 1));
    await commands.releaseHolds([17]);
    expect(calls, ['release_blueprint_holds_client_sync_v1']);
  });

  test('ticket cancellation uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseTicketCommands.withTransport(
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
          'data': {
            'cancelledOrderIds': [5],
            'updatedOrders': [
              {'id': 6, 'email': 'owner@example.test'}
            ],
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
                'mutation': {
                  'commandId': '00000000-0000-4000-8000-000000000001',
                  'receiptId': '00000000-0000-4000-8000-000000000001',
                  'commitId': null,
                  'replayed': false,
                  'occurredAt': '2026-10-15T10:00:00Z'
                },
                'status': 'rejected',
                'code': 403,
                'data': {
                  'updatedOrders': [
                    {'id': 6, 'email': 'owner@example.test'}
                  ]
                },
                'sync': {'replacements': <Object>[]},
              },
          maxAttempts: 1),
    );
    await expectLater(
        commands.cancel([1]),
        throwsA(isA<BlueprintCommandRejection>()
            .having((e) => e.code, 'code', 403)));
  });
}
