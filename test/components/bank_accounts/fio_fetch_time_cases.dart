import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/bank_account_model.dart';

void main() {
  test('Email update is not treated as a successful FIO fetch', () {
    final account = BankAccountModel.fromJson({
      'id': 1,
      'last_fetch_time': '2026-10-02T12:00:00Z',
    });
    expect(account.lastFetchTime, isNotNull);
    expect(account.lastFioFetchTime, isNull);
  });

  test('FIO success survives serialization and account edits', () {
    final account = BankAccountModel.fromJson({
      'id': 1,
      'last_fio_fetch_time': '2026-10-02T12:00:00Z',
    });
    final edited = account.copyWith(title: 'Updated');
    expect(edited.lastFioFetchTime, DateTime.utc(2026, 10, 2, 12));
    expect(BankAccountModel.fromJson(edited.toJson()).lastFioFetchTime,
        account.lastFioFetchTime);
  });
}
