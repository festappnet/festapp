import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/reception/reception_service.dart';

void main() {
  test('existing e-mail conflict is a user-correctable reception error', () {
    final error = ReceptionCommandException({
      'code': 409,
      'message': 'email_already_exists',
    });

    expect(error.kind, ReceptionCommandError.emailAlreadyExists);
  });

  test('unknown command failures stay classified as unexpected', () {
    final error = ReceptionCommandException({
      'code': 500,
      'message': 'future_server_failure',
    });

    expect(error.kind, ReceptionCommandError.unexpected);
  });
}
