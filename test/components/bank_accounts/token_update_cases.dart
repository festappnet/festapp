import 'dart:convert';
import 'package:festapp_core/eshop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fstapp/components/bank_accounts/supabase_bank_accounts.dart';
import '../../support/fixtures/supabase_client_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic> outcome = {};
  late SupabaseClientFixture fixture;
  late SupabaseBankAccounts commands;
  setUp(() {
    calls.clear();
    outcome = {};
    fixture = SupabaseClientFixture((request) async {
          if (request.url.path == '/rest/v1/rpc/update_bank_account') {
            calls.add({
              'operation': 'update_bank_account',
              ...jsonDecode(request.body)
            });
            return http.Response('159', 200,
                request: request,
                headers: {'content-type': 'application/json'});
          }
          expect(request.url.path, '/functions/v1/bank-sync-manage');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          calls.add(body);
          if (body['operation'] == 'status') {
            return http.Response(
                jsonEncode({'id': 1, 'state': 'connected', 'mode': 'api'}), 200,
                headers: {'content-type': 'application/json'});
          }
          return http.Response(jsonEncode(outcome), 200,
              headers: {'content-type': 'application/json'});
    });
    addTearDown(fixture.dispose);
    commands = SupabaseBankAccounts(fixture.client);
  });

  test('Update token sends the new value to the BankSync management endpoint',
      () async {
    outcome = {'state': 'connected', 'token_saved': true};
    await commands.updateBankAccountToken(
        159, 'new-fixture-token', DateTime.utc(2027, 1, 1));
    expect(calls.map((c) => c['operation']), ['status', 'set_token']);
    expect(calls.last['account_id'], 159);
    expect(calls.last['token'], 'new-fixture-token');
    expect(calls.last['expiry'], '2027-01-01T00:00:00.000Z');
    expect(calls.last['operation_id'], isNotEmpty);
  });
  test('Stored but inactive token is not reported as fully connected',
      () async {
    outcome = {
      'state': 'degraded',
      'token_saved': true,
      'verification_error': 'fio_token_invalid_or_inactive'
    };
    await expectLater(
        commands.updateBankAccountToken(
            159, 'inactive-fixture-token', null),
        throwsA(isA<BankSyncError>()
            .having((e) => e.code, 'code', 'fio_token_invalid_or_inactive')
            .having((e) => e.tokenSaved, 'stored', true)));
    final previousId = calls.last['operation_id'];
    outcome = {'state': 'connected', 'token_saved': true};
    await commands.updateBankAccountToken(
        159, 'replacement-fixture-token', null);
    expect(calls.last['operation_id'], isNot(previousId));
    expect(calls.last['token'], 'replacement-fixture-token');
  });
  test(
      'Uncertain retry keeps its intent but a corrected token gets a new intent',
      () async {
    outcome = {'error': 'bank_sync_retry_required'};
    await expectLater(
        commands.updateBankAccountToken(160, 'first-token', null),
        throwsA(isA<BankSyncError>()));
    final firstId = calls.last['operation_id'];
    await expectLater(
        commands.updateBankAccountToken(160, 'first-token', null),
        throwsA(isA<BankSyncError>()));
    expect(calls.last['operation_id'], firstId);
    await expectLater(
        commands.updateBankAccountToken(160, 'corrected-token', null),
        throwsA(isA<BankSyncError>()));
    expect(calls.last['operation_id'], isNot(firstId));
  });
  test('Saving account details immediately flushes the durable BankSync update',
      () async {
    outcome = {'details_saved': true};
    final account = BankAccountModel(
        id: 159,
        accountNumber: 'CZ6508000000192000145399',
        title: 'New label',
        type: 'FIO');
    expect(await commands.updateBankAccount(account), 159);
    expect(calls.map((c) => c['operation']),
        ['update_bank_account', 'update_details']);
    expect(calls.first['p_title'], 'New label');
    expect(calls.last['account_id'], 159);
    outcome = {'error': 'bank_sync_retry_required'};
    await expectLater(commands.updateBankAccount(account),
        throwsA(isA<BankSyncError>()));
  });
  test('Wrong-account token preserves the specific bank error', () async {
    outcome = {
      'token_saved': true,
      'verification_error': 'fio_receiving_account_mismatch'
    };
    await expectLater(
        commands.updateBankAccountToken(
            159, 'wrong-account-fixture', null),
        throwsA(isA<BankSyncError>()
            .having((e) => e.code, 'code', 'fio_receiving_account_mismatch')
            .having((e) => e.tokenSaved, 'saved', true)));
  });
}
