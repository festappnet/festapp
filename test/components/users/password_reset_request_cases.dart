import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/password_reset_request.dart';

void main() {
  test('reports success after the reset request completes', () async {
    String? requestedEmail;

    final result = await requestPasswordReset(
      email: 'user@example.test',
      send: (email) async => requestedEmail = email,
    );

    expect(result, PasswordResetRequestResult.sent);
    expect(requestedEmail, 'user@example.test');
  });

  test('reports failure when the reset request throws', () async {
    final result = await requestPasswordReset(
      email: 'user@example.test',
      send: (_) async => throw Exception('delivery failed'),
    );

    expect(result, PasswordResetRequestResult.failed);
  });

  test('reports missing email without sending a request', () async {
    var wasCalled = false;

    final result = await requestPasswordReset(
      email: '  ',
      send: (_) async => wasCalled = true,
    );

    expect(result, PasswordResetRequestResult.missingEmail);
    expect(wasCalled, isFalse);
  });
}
