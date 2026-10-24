import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/account_deletion_service.dart';

void main() {
  test('maps the email-confirmation response without sending identity fields',
      () async {
    var calls = 0;
    final service = AccountDeletionService(invoke: () async {
      calls++;
      return {
        'status': 'email_sent',
        'maskedEmail': 'a***@example.test',
        'expiresAt': '2026-08-04T12:00:00Z',
      };
    });
    final result = await service.request();
    expect(calls, 1);
    expect(result.maskedEmail, 'a***@example.test');
    expect(result.expiresAt.isUtc, isTrue);
  });

  test('does not report an unsuccessful request as email sent', () async {
    final service = AccountDeletionService(
      invoke: () async => {'error': 'cooldown'},
    );
    await expectLater(
        service.request(), throwsA(isA<AccountDeletionException>()));
  });
}
