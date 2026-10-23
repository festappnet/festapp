import 'dart:async';
import 'package:fstapp/components/blueprint/blueprint_hold_release_preview.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
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
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
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

  test(
      'temporary hold release preserves the exact server preview and command across a lost response',
      () async {
    final calls = <Map<String, dynamic>>[];
    var lose = true;
    final snapshot = List.filled(64, 'a').join();
    final commands = SupabaseTicketCommands.withTransport(
      ClientCommandTransport((name, params) async {
        expect(name, 'release_blueprint_holds');
        calls.add(params);
        if (lose) {
          lose = false;
          throw TimeoutException('response lost');
        }
        return commandResponseFixture(params['p_command_id'] as String, data: {
          'spotIds': [17, 18]
        });
      }),
      readRpc: (name, params) async {
        expect(name, 'preview_blueprint_hold_release');
        expect(params['p_spots'], [17]);
        expect(params.containsKey('p_command_id'), isFalse);
        return {
          'occasionId': 7,
          'blueprintId': 9,
          'layoutRevision': 3,
          'requestedSpotIds': [17],
          'affectedSpotIds': [17, 18],
          'holdSnapshot': snapshot,
          'activeHoldCount': 2,
          'canApply': true,
          'seats': [
            {'spotId': 17, 'title': 'A', 'state': 'selected'},
            {'spotId': 18, 'title': 'B', 'state': 'selected'},
          ],
        };
      },
    );
    final preview = await commands
        .previewHoldRelease([17], occasionId: 7, organizationId: 2, unitId: 4);
    expect(() => preview.affectedSpotIds.clear(), throwsUnsupportedError);
    await commands.releaseHolds(preview);
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls.first['p_affected_spots'], [17, 18]);
    expect(calls.first['p_hold_snapshot'], snapshot);
    expect(calls.first['p_expected_revision'], 3);
    expect(calls.first['p_organization'], 2);
  });

  test('hold preview refuses a confirmation with a missing companion row', () {
    expect(
        () => BlueprintHoldReleasePreview.fromJson({
              'occasionId': 7,
              'blueprintId': 9,
              'layoutRevision': 3,
              'requestedSpotIds': [17],
              'affectedSpotIds': [17, 18],
              'holdSnapshot': List.filled(64, 'a').join(),
              'activeHoldCount': 2,
              'canApply': true,
              'seats': [
                {'spotId': 17, 'title': 'A', 'state': 'selected'}
              ],
            }, organizationId: 2),
        throwsFormatException);
  });

  test('ticket cancellation uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseTicketCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
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
                  'commandId': params['p_command_id'],
                  'receiptId': params['p_command_id'],
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
