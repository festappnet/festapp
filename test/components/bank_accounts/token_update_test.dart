import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/components/bank_accounts/db_bank_accounts.dart';
import 'package:fstapp/components/bank_accounts/bank_sync_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final calls = <Map<String, dynamic>>[];
  Map<String, dynamic> outcome = {};
  setUpAll(() async {
    await Supabase.initialize(
        url: 'https://local-test.invalid',
        anonKey: 'synthetic-test-key',
        authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
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
        }));
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });
  setUp(() {
    calls.clear();
  });

  test('Update token sends the new value to the BankSync management endpoint',
      () async {
    outcome = {'state': 'connected', 'token_saved': true};
    await DbBankAccounts.updateBankAccountToken(
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
        DbBankAccounts.updateBankAccountToken(
            159, 'inactive-fixture-token', null),
        throwsA(isA<BankSyncError>()
            .having((e) => e.code, 'code', 'fio_token_invalid_or_inactive')
            .having((e) => e.tokenSaved, 'stored', true)));
    final previousId = calls.last['operation_id'];
    outcome = {'state': 'connected', 'token_saved': true};
    await DbBankAccounts.updateBankAccountToken(
        159, 'replacement-fixture-token', null);
    expect(calls.last['operation_id'], isNot(previousId));
    expect(calls.last['token'], 'replacement-fixture-token');
  });
  test(
      'Uncertain retry keeps its intent but a corrected token gets a new intent',
      () async {
    outcome = {'error': 'bank_sync_retry_required'};
    await expectLater(
        DbBankAccounts.updateBankAccountToken(160, 'first-token', null),
        throwsA(isA<BankSyncError>()));
    final firstId = calls.last['operation_id'];
    await expectLater(
        DbBankAccounts.updateBankAccountToken(160, 'first-token', null),
        throwsA(isA<BankSyncError>()));
    expect(calls.last['operation_id'], firstId);
    await expectLater(
        DbBankAccounts.updateBankAccountToken(160, 'corrected-token', null),
        throwsA(isA<BankSyncError>()));
    expect(calls.last['operation_id'], isNot(firstId));
  });
}
