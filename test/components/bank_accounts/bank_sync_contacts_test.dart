import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/bank_accounts/bank_sync_warning.dart';

void main() {
  test('same delivery address deduplicates migrated identities and trims text',
      () {
    final warning = BankSyncWarning.fromJson({
      'code': 'suspended',
      'contacts': [
        {'name': ' Michael ', 'email': 'MAIL@example.test'},
        {'name': 'Michael', 'email': ' mail@EXAMPLE.test '},
        {'name': 'Another admin', 'email': 'another@example.test'},
      ],
    });
    expect(warning.uniqueContacts.length, 2);
    expect(warning.uniqueContacts.first.name, 'Michael');
    expect((warning.toJson()['contacts'] as List).length, 2);
  });
  test('fallback names deduplicate without merging different addresses', () {
    const warning =
        BankSyncWarning(code: 'stale', bankAccountTitle: '', contacts: [
      BankSyncContact(name: 'Jane Admin'),
      BankSyncContact(name: ' jane   admin '),
      BankSyncContact(name: 'Jane Admin', email: 'one@example.test'),
      BankSyncContact(name: 'Jane Admin', email: 'two@example.test'),
      BankSyncContact(name: '   ', email: ''),
    ]);
    expect(warning.uniqueContacts.length, 3);
  });
  test('richer duplicate supplies missing administrator name', () {
    const warning =
        BankSyncWarning(code: 'stale', bankAccountTitle: '', contacts: [
      BankSyncContact(name: '', email: 'admin@example.test'),
      BankSyncContact(name: 'Jane Admin', email: 'ADMIN@example.test'),
    ]);
    expect(warning.uniqueContacts.single.name, 'Jane Admin');
  });
}
