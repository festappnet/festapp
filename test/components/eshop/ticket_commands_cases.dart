import '../../support/fixtures/blueprint_swap_preview_fixture.dart';
import '../../support/fixtures/local_storage_fixture.dart';
import 'package:fstapp/components/blueprint/blueprint_seat_swap_preview.dart';
import 'dart:async';
import 'package:fstapp/components/blueprint/blueprint_hold_release_preview.dart';
import '../../support/fixtures/client_command_response_fixture.dart';
import 'package:fstapp/components/blueprint/blueprint_command_rejection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerLocalStorageFixture();
  test(
      'confirmed swap retains expanded seats and exact money intent across a lost response',
      () async {
    final raw = blueprintSwapPreviewFixture();
    final preview =
        BlueprintSeatSwapPreview.fromJson(raw, organizationId: 3, unitId: 7);
    (raw['sourceSpotIds'] as List).clear();
    expect(preview.sourceSpotIds, [11, 15]);
    expect(() => preview.sourceSpotIds.add(99), throwsUnsupportedError);
    expect(() => preview.sourceIds.add(99), throwsUnsupportedError);
    final calls = <Map<String, dynamic>>[];
    final commands = SupabaseTicketCommands.withTransport(
        ClientCommandTransport((name, args) async {
      expect(name, 'swap_blueprint_seats');
      calls.add(args);
      if (calls.length == 1) throw TimeoutException('lost after SQL commit');
      return commandResponseFixture(args['p_command_id'] as String);
    }));
    await commands.swapSpots(preview);
    expect(calls, hasLength(2));
    expect(calls[0], calls[1]);
    expect(calls.first['p_first'], 11);
    expect(calls.first['p_second'], 13);
    expect(calls.first['p_source_spots'], [11, 15]);
    expect(calls.first['p_target_spots'], [13, 14]);
    expect(calls.first['p_expected_revision'], 1);
    expect(calls.first['p_confirmation_hash'], preview.confirmationHash);
  });

  test('swap preview refuses missing expanded seats or order effects', () {
    final missingSeat = blueprintSwapPreviewFixture();
    (missingSeat['seats'] as List).removeLast();
    expect(
        () => BlueprintSeatSwapPreview.fromJson(missingSeat, organizationId: 3),
        throwsFormatException);
    final missingMoney = blueprintSwapPreviewFixture();
    missingMoney['orders'] = [];
    expect(
        () =>
            BlueprintSeatSwapPreview.fromJson(missingMoney, organizationId: 3),
        throwsFormatException);
  });

  test(
      'new adapter recovers a persisted uncertain swap before any inverse preview or new command',
      () async {
    final preview = BlueprintSeatSwapPreview.fromJson(
        blueprintSwapPreviewFixture(),
        organizationId: 3,
        unitId: 7);
    final calls = <Map<String, dynamic>>[];
    final first = SupabaseTicketCommands.withTransport(
        ClientCommandTransport((name, args) async {
      expect(name, 'swap_blueprint_seats');
      calls.add(args);
      throw TimeoutException('commit outcome lost');
    }, principalBinding: 'synthetic-swap-recovery-actor'));
    await expectLater(
        first.swapSpots(preview), throwsA(isA<TimeoutException>()));
    expect(calls, hasLength(2));
    final reopened = SupabaseTicketCommands.withTransport(
        ClientCommandTransport((name, args) async {
          expect(name, 'swap_blueprint_seats');
          calls.add(args);
          return commandResponseFixture(args['p_command_id'] as String);
        }, principalBinding: 'synthetic-swap-recovery-actor'),
        readRpc: (_, __) async => throw StateError(
            'Never preview the inverse while the first result is unknown'));
    await expectLater(
        reopened.recoverSwap(
            occasionId: 1, organizationId: 3, unitId: 7, blueprintId: 2),
        throwsA(isA<BlueprintCommandRejection>()));
    expect(calls, hasLength(2),
        reason: 'A different map cannot resume this intent');
    expect(
        await reopened.recoverSwap(
            occasionId: 1, organizationId: 3, unitId: 7, blueprintId: 1),
        isTrue);
    expect(calls, hasLength(3));
    expect(calls[2], calls[0]);
    expect(
        await reopened.recoverSwap(
            occasionId: 1, organizationId: 3, unitId: 7, blueprintId: 1),
        isFalse);
  });

  test(
      'expired swap outcome retains its original intent and prevents a fresh swap',
      () async {
    final preview = BlueprintSeatSwapPreview.fromJson(
        blueprintSwapPreviewFixture(),
        organizationId: 3,
        unitId: 7);
    final calls = <Map<String, dynamic>>[];
    final first = SupabaseTicketCommands.withTransport(
        ClientCommandTransport((_, args) async {
      calls.add(args);
      throw TimeoutException('outcome unknown');
    }, maxAttempts: 1, principalBinding: 'synthetic-expired-swap'));
    await expectLater(
        first.swapSpots(preview), throwsA(isA<TimeoutException>()));
    final recovery = SupabaseTicketCommands.withTransport(
        ClientCommandTransport((_, args) async {
      calls.add(args);
      return commandResponseFixture(args['p_command_id'] as String,
          status: 'expired', code: 410);
    }, principalBinding: 'synthetic-expired-swap'));
    await expectLater(
        recovery.recoverSwap(
            occasionId: 1, organizationId: 3, unitId: 7, blueprintId: 1),
        throwsA(isA<BlueprintCommandRejection>().having(
            (e) => e.reason, 'reason', 'BLUEPRINT_SWAP_RECOVERY_REQUIRED')));
    expect(calls, hasLength(2));
    expect(calls.last['p_command_id'], calls.first['p_command_id']);
    final changed = blueprintSwapPreviewFixture();
    changed['confirmationHash'] = List.filled(64, 'c').join();
    await expectLater(
        recovery.swapSpots(BlueprintSeatSwapPreview.fromJson(changed,
            organizationId: 3, unitId: 7)),
        throwsStateError);
    expect(calls, hasLength(2),
        reason: 'No new RPC or UUID may force an unresolved intent through');
  });

  test('preview discards a prior actors response after the principal changes',
      () async {
    var actor = 'preview-actor-before';
    final response = Completer<Object?>();
    final commands = SupabaseTicketCommands.withTransport(
        ClientCommandTransport(
            (_, __) async => throw StateError('A preview never writes'),
            principalProvider: () => actor),
        readRpc: (_, __) => response.future);
    final pending =
        commands.previewHoldRelease([1], occasionId: 1, organizationId: 3);
    actor = 'preview-actor-after';
    response.complete({
      'occasionId': 1,
      'blueprintId': 1,
      'layoutRevision': 1,
      'requestedSpotIds': [1],
      'affectedSpotIds': [1],
      'holdSnapshot': List.filled(64, 'a').join(),
      'seats': [
        {'spotId': 1, 'title': 'Prior actor seat', 'state': 'available'}
      ],
      'activeHoldCount': 0,
      'canApply': true
    });
    await expectLater(
        pending,
        throwsA(isA<StateError>().having(
            (e) => e.message, 'identity guard', 'COMMAND_PRINCIPAL_CHANGED')));
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
