import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/password_change_flow.dart';

void main() {
  test('changes the password and signs the user in', () async {
    final result = await completePasswordChange(
      token: 'token',
      password: 'new-password',
      change: (_, __) async => {'code': 200, 'email': 'user@example.test'},
      signIn: (_, __) async {},
    );

    expect(result, PasswordChangeResult.changedAndSignedIn);
  });

  test('reports an invalid or already consumed token', () async {
    final result = await completePasswordChange(
      token: 'token',
      password: 'new-password',
      change: (_, __) async => {'code': 403},
      signIn: (_, __) async {},
    );

    expect(result, PasswordChangeResult.invalidToken);
  });

  test('keeps password-change success when automatic sign-in fails', () async {
    final result = await completePasswordChange(
      token: 'token',
      password: 'new-password',
      change: (_, __) async => {'code': 200, 'email': 'user@example.test'},
      signIn: (_, __) async => throw Exception('sign-in failed'),
    );

    expect(result, PasswordChangeResult.changedSignInRequired);
  });

  test('reports malformed and unexpected responses as failures', () async {
    final result = await completePasswordChange(
      token: 'token',
      password: 'new-password',
      change: (_, __) async => {'code': 500},
      signIn: (_, __) async {},
    );

    expect(result, PasswordChangeResult.failed);
  });
}
