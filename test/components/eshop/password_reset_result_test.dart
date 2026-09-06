import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/eshop/db_tickets.dart';

void main() {
  test('password reset result identifies a privileged target denial', () {
    final result = PasswordResetResult.fromRpcResponse({
      'code': 403,
      'message':
          'Security Restriction: Cannot reset password for privileged users via scan.',
    });

    expect(result.email, isNull);
    expect(result.failure, PasswordResetFailure.privilegedTarget);
  });

  test('password reset result does not expose unexpected RPC details', () {
    final result = PasswordResetResult.fromRpcResponse({
      'code': 500,
      'message': 'internal database detail',
    });

    expect(result.email, isNull);
    expect(result.failure, isNull);
  });
}
