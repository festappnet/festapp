import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/eshop/ticket_batch_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import '../../support/fixtures/local_app_storage_fixture.dart';

Map<String, dynamic> receipt() => {
      'code': 200,
      'status': 'applied',
      'data': {'orderId': 7, 'transactionId': 9},
      'sync': {'replacements': <Object>[]}
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'sale retries serialization with the same command, exact selected IDs and no client money',
      () async {
    final calls = <Map<String, dynamic>>[];
    final commands = SupabaseTicketBatchCommands.withTransport(
        ClientCommandTransport((rpc, params) async {
      expect(rpc, 'sell_ticket_batch_items_client_sync_v1');
      calls.add({...params});
      if (calls.length == 1) {
        throw const PostgrestException(
            message: 'ticket_parent_changed', code: '40001');
      }
      return receipt();
    }, retrySerialization: true));
    await commands.sell(
        batchId: 'batch',
        ticketIds: [3, 1, 3],
        contact: {'email': 'fixture@example.invalid'});
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls.last['p_tickets'], [1, 3]);
    expect(calls.last.keys.toSet(), {
      'p_batch',
      'p_tickets',
      'p_contact',
      'p_send_tickets',
      'p_command_id'
    });
    expect(calls.last['p_send_tickets'], false);
  });
  test(
      'reload resumes the durable sale with original selection and receipt then clears intent',
      () async {
    final fixture = await LocalAppStorageFixture.open();
    addTearDown(fixture.dispose);
    String? original;
    final offline = SupabaseTicketBatchCommands.withTransport(
        ClientCommandTransport((rpc, params) async {
      original = params['p_command_id'] as String;
      throw TimeoutException('response lost after commit');
    }, maxAttempts: 1, principalBinding: 'batch-fixture:actor'));
    await expectLater(offline.sell(batchId: 'batch', ticketIds: [2, 1]),
        throwsA(isA<TimeoutException>()));
    final resumed = SupabaseTicketBatchCommands.withTransport(
        ClientCommandTransport((rpc, params) async {
      expect(params['p_command_id'], original);
      expect(params['p_tickets'], [1, 2]);
      return receipt();
    }, principalBinding: 'batch-fixture:actor'));
    expect((await resumed.recoverPendingSale('batch'))?['orderId'], 7);
    expect(await resumed.recoverPendingSale('batch'), null);
  });
  test(
      'invalid email never leaves a durable sale intent blocking a corrected sale',
      () async {
    final fixture = await LocalAppStorageFixture.open();
    addTearDown(fixture.dispose);
    var calls = 0;
    final commands = SupabaseTicketBatchCommands.withTransport(
        ClientCommandTransport((rpc, params) async {
      calls++;
      return receipt();
    }, principalBinding: 'validated-batch:actor'));
    await expectLater(
        commands.sell(
            batchId: 'batch',
            ticketIds: [1],
            contact: {'email': 'invalid'},
            sendTickets: true),
        throwsArgumentError);
    expect(calls, 0);
    expect(
        (await commands.sell(
            batchId: 'batch',
            ticketIds: [1],
            contact: {'email': 'valid@example.invalid'},
            sendTickets: true))['orderId'],
        7);
    expect(calls, 1);
  });
}
